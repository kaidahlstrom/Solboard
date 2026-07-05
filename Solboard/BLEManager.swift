//
//  BLEManager.swift
//  Solboard
//
//  CoreBluetooth is the ONLY radio this app uses (see CLAUDE.md hard constraints).
//  Scans for the LED box, connects, discovers the Nordic-UART RX characteristic,
//  and writes route command strings. Auto-reconnects to the last box on launch.
//

import Foundation
import Combine
import CoreBluetooth

enum ConnectionStatus: Equatable {
    case poweredOff
    case disconnected
    case scanning
    case connecting(String)
    case connected(String)

    var label: String {
        switch self {
        case .poweredOff:          return "Bluetooth off"
        case .disconnected:        return "Disconnected"
        case .scanning:            return "Scanning…"
        case .connecting(let n):   return "Connecting to \(n)…"
        case .connected(let n):    return "Connected: \(n)"
        }
    }
}

/// A peripheral surfaced during scanning, for the Connect screen list.
struct DiscoveredPeripheral: Identifiable, Equatable {
    let id: UUID
    let name: String
    let peripheral: CBPeripheral

    static func == (a: DiscoveredPeripheral, b: DiscoveredPeripheral) -> Bool { a.id == b.id }
}

@MainActor
final class BLEManager: NSObject, ObservableObject {
    @Published private(set) var status: ConnectionStatus = .disconnected
    /// Every named peripheral seen this scan. The Connect list shows `visibleDevices`.
    @Published private(set) var discovered: [DiscoveredPeripheral] = []
    /// Escape hatch for first contact: show unfiltered results if the real box's
    /// advertised name doesn't match our MoonBoard heuristic. Toggled from the UI.
    @Published var showAllDevices = false
    /// Set after a failed/successful send so the UI can surface a one-line result.
    @Published var lastSendError: String?

    private var central: CBCentralManager!
    private var connected: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    private let serviceUUID = CBUUID(string: MoonBoardProtocol.uartService)
    private let rxUUID = CBUUID(string: MoonBoardProtocol.uartRX)

    /// Restrict scanning to the Nordic UART service. Confirmed on-site, so this is
    /// on. Set false only to troubleshoot if the box stops advertising the service.
    private let filterScanByService = true

    private let lastPeripheralKey = "lastPeripheralUUID"

    /// The Connect-tab list: all named devices when `showAllDevices`, otherwise
    /// only those whose name looks like a MoonBoard box.
    var visibleDevices: [DiscoveredPeripheral] {
        showAllDevices ? discovered : discovered.filter { Self.looksLikeMoonBoard($0.name) }
    }

    /// Name contains "moon" (any case), or is a bare 12-digit numeric ID (some
    /// boxes advertise a serial). Heuristic only — the toggle is the fallback.
    static func looksLikeMoonBoard(_ name: String) -> Bool {
        if name.lowercased().contains("moon") { return true }
        return name.range(of: "^[0-9]{12}$", options: .regularExpression) != nil
    }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    var isReady: Bool { writeCharacteristic != nil }

    // MARK: Scanning / connecting

    func startScan() {
        guard central.state == .poweredOn else { return }
        discovered.removeAll()
        status = .scanning
        let services: [CBUUID]? = filterScanByService ? [serviceUUID] : nil
        central.scanForPeripherals(withServices: services)
    }

    func stopScan() {
        central.stopScan()
        if case .scanning = status { status = .disconnected }
    }

    func connect(_ item: DiscoveredPeripheral) {
        central.stopScan()
        connect(item.peripheral, name: item.name)
    }

    private func connect(_ peripheral: CBPeripheral, name: String) {
        connected = peripheral
        peripheral.delegate = self
        status = .connecting(name)
        central.connect(peripheral)
    }

    func disconnect() {
        if let p = connected { central.cancelPeripheralConnection(p) }
    }

    /// Reconnect to the last box we used, without showing the scan UI.
    private func reconnectLast() {
        guard let idString = UserDefaults.standard.string(forKey: lastPeripheralKey),
              let uuid = UUID(uuidString: idString),
              let peripheral = central.retrievePeripherals(withIdentifiers: [uuid]).first
        else { return }
        connect(peripheral, name: peripheral.name ?? "MoonBoard")
    }

    // MARK: Sending

    /// Write a route to the board. Safe to call when not ready — it just reports.
    func send(_ holds: [Hold]) {
        guard let peripheral = connected, let tx = writeCharacteristic else {
            lastSendError = "Not connected"
            return
        }
        lastSendError = nil
        let data = MoonBoardProtocol.payload(for: holds)
        // A full route is a short ASCII string (well under the BLE MTU), so no
        // chunking is needed. Prefer write-without-response when supported.
        let type: CBCharacteristicWriteType =
            tx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: tx, type: type)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if case .connected = status { break }
                status = .disconnected
                reconnectLast()
            case .poweredOff:
                status = .poweredOff
            default:
                status = .disconnected
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        guard let name, !name.isEmpty else { return }   // hide unnamed noise
        let item = DiscoveredPeripheral(id: peripheral.identifier, name: name, peripheral: peripheral)
        Task { @MainActor in
            if !discovered.contains(item) { discovered.append(item) }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastPeripheralKey)
            peripheral.discoverServices([serviceUUID])   // confirmed on-site
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            connected = nil
            status = .disconnected
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            connected = nil
            writeCharacteristic = nil
            status = .disconnected
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        Task { @MainActor in
            for char in service.characteristics ?? [] {
                // Match the confirmed RX (write) UUID; fall back to any writable
                // characteristic as a safety net.
                let writable = char.properties.contains(.write)
                    || char.properties.contains(.writeWithoutResponse)
                if char.uuid == rxUUID || (writeCharacteristic == nil && writable) {
                    writeCharacteristic = char
                    status = .connected(peripheral.name ?? "MoonBoard")
                }
            }
        }
    }
}
