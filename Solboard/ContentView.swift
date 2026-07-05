//
//  ContentView.swift
//  Solboard
//
//  Three screens: Board (edit + light a route), Presets, Connect. Stock SwiftUI.
//

import SwiftUI
import UIKit

struct ContentView: View {
    enum Tab { case board, presets, connect }

    // The route currently on the grid — shared so presets can load into it.
    @State private var grid = BoardGrid()
    @State private var selectedTab: Tab = .board
    @StateObject private var ble = BLEManager()
    @StateObject private var presets = PresetStore()

    var body: some View {
        TabView(selection: $selectedTab) {
            BoardView(grid: $grid, ble: ble) { name in
                presets.add(name: name, holds: grid.holds)
            }
            .tabItem { Label("Board", systemImage: "square.grid.3x3") }
            .tag(Tab.board)

            PresetsView(presets: presets) { preset in
                grid = BoardGrid(holds: preset.holds)
                selectedTab = .board          // jump to the board to see the loaded route
            }
            .tabItem { Label("Presets", systemImage: "list.bullet") }
            .tag(Tab.presets)

            ConnectView(ble: ble)
                .tabItem { Label("Connect", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.connect)
        }
    }
}

// MARK: - Board

struct BoardView: View {
    @Binding var grid: BoardGrid
    @ObservedObject var ble: BLEManager
    /// Called with a preset name when the user taps Save.
    let onSave: (String) -> Void

    @State private var showingSave = false
    @State private var presetName = ""
    /// DEBUG-only: draw every cell outline over the image to judge alignment.
    @State private var calibrating = false
    /// DEBUG-only: reveal the write-path diagnostics panel.
    @State private var showDebug = false

    /// User-supplied board photo (gitignored, never redistributed). Absent = fallback grid.
    private var boardImage: UIImage? { UIImage(named: "board") }

    var body: some View {
        VStack(spacing: 12) {
            statusBar

            if let img = boardImage, img.size.width > 0, img.size.height > 0 {
                boardImageView(img)
            } else {
                plainGrid
            }

            buttonRow

            #if DEBUG
            if showDebug { debugPanel }
            #endif
        }
        .padding()
        .alert("Save preset", isPresented: $showingSave) {
            TextField("Name", text: $presetName)
            Button("Save") {
                let name = presetName.trimmingCharacters(in: .whitespaces)
                onSave(name.isEmpty ? "Route" : name)
                presetName = ""
            }
            Button("Cancel", role: .cancel) { presetName = "" }
        }
    }

    #if DEBUG
    /// TEMPORARY on-screen write-path diagnostics. Remove with BLEDebug once fixed.
    private var debugPanel: some View {
        let d = ble.debug
        return VStack(alignment: .leading, spacing: 2) {
            Text("DEBUG · write path").font(.system(size: 10, weight: .bold, design: .monospaced))
            Text("peripheral: \(d.peripheralName ?? "—")")
            Text("writeChar: \(d.characteristicUUID ?? "nil")")
                .foregroundStyle(d.characteristicUUID == nil ? Color.red : Color.secondary)
            Text("props: [\(d.characteristicProps ?? "—")]  type: \(d.lastWriteType ?? "—")")
            Text("chunks: \(d.chunkCount) @ maxLen \(d.maxWriteLen)")
            Text("ack: \(d.lastWriteAck ?? "—")  taps: \(d.sendCount)")
            Text("payload: \(d.lastPayload ?? "—")")
            Text("bytes: \(d.lastBytesHex ?? "—")")
            Text("error: \(d.lastError ?? "none")")
                .foregroundStyle(d.lastError == nil ? Color.secondary : Color.red)
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    #endif

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(ble.isReady ? .green : .secondary)
                .frame(width: 10, height: 10)
            Text(ble.status.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            #if DEBUG
            Toggle("Calibrate", isOn: $calibrating)
                .toggleStyle(.button)
                .font(.caption)
            Toggle("Debug", isOn: $showDebug)
                .toggleStyle(.button)
                .font(.caption)
            #endif
        }
    }

    // MARK: Plain grid (fallback when no board image is supplied)

    private var plainGrid: some View {
        GeometryReader { geo in
            let cell = min(geo.size.width / CGFloat(MoonBoardProtocol.columns),
                           geo.size.height / CGFloat(MoonBoardProtocol.rows))
            // Rows drawn top-down: label 18 at the top, label 1 at the bottom.
            VStack(spacing: 1) {
                ForEach((0..<MoonBoardProtocol.rows).reversed(), id: \.self) { row in
                    HStack(spacing: 1) {
                        ForEach(0..<MoonBoardProtocol.columns, id: \.self) { col in
                            cellView(col: col, row: row, side: cell)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func cellView(col: Int, row: Int, side: CGFloat) -> some View {
        let type = grid.type(col: col, row: row)
        return Text("\(MoonBoardProtocol.columnLabel(col))\(MoonBoardProtocol.rowLabel(row))")
            .font(.system(size: 8))
            .foregroundStyle(type == nil ? Color.secondary : Color.white)
            .frame(width: side, height: side)
            .background(color(for: type))
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .contentShape(Rectangle())
            .onTapGesture { grid.cycle(col: col, row: row) }
    }

    // MARK: Board image with transparent tap cells + colored hold rings

    private func boardImageView(_ img: UIImage) -> some View {
        ZStack {
            Image(uiImage: img)
                .resizable()
            GeometryReader { geo in
                holdsOverlay(in: geo.size)
            }
        }
        // Match the image's aspect ratio exactly so the overlay maps 1:1 with
        // no letterboxing — cell centers then align with the calibrated insets.
        .aspectRatio(img.size.width / img.size.height, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func holdsOverlay(in size: CGSize) -> some View {
        let ins = MoonBoardProtocol.imageInsets
        let left = size.width * ins.left
        let top = size.height * ins.top
        let gridW = size.width * (1 - ins.left - ins.right)
        let gridH = size.height * (1 - ins.top - ins.bottom)
        let cellW = gridW / CGFloat(MoonBoardProtocol.columns)
        let cellH = gridH / CGFloat(MoonBoardProtocol.rows)
        return ForEach(0..<MoonBoardProtocol.rows, id: \.self) { row in
            ForEach(0..<MoonBoardProtocol.columns, id: \.self) { col in
                let cx = left + (CGFloat(col) + 0.5) * cellW
                // row 0 is the bottom of the board, so it maps to the bottom of the image.
                let cy = top + (CGFloat(MoonBoardProtocol.rows - 1 - row) + 0.5) * cellH
                holdCell(col: col, row: row, cellW: cellW, cellH: cellH)
                    .position(x: cx, y: cy)
            }
        }
    }

    private func holdCell(col: Int, row: Int, cellW: CGFloat, cellH: CGFloat) -> some View {
        let type = grid.type(col: col, row: row)
        let dot = min(cellW, cellH) * MoonBoardProtocol.ledDotSize
        return ZStack {
            // Calibration: outline every cell so grid-vs-hold alignment is obvious.
            if calibrating {
                Rectangle()
                    .strokeBorder(Color.yellow, lineWidth: 0.75)
                    .frame(width: cellW, height: cellH)
                Text("\(MoonBoardProtocol.columnLabel(col))\(MoonBoardProtocol.rowLabel(row))")
                    .font(.system(size: 6))
                    .foregroundStyle(Color.yellow)
            }
            // Lit hold: a filled LED dot just BELOW the hold, like the real board
            // where the LEDs sit under each hold. Offset ~40% of a cell downward.
            if let type {
                Circle()
                    .fill(color(for: type))
                    .frame(width: dot, height: dot)
                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.5))
                    .shadow(color: color(for: type).opacity(0.7), radius: dot * 0.35)
                    .offset(y: cellH * MoonBoardProtocol.ledDotOffset)
            }
        }
        .frame(width: cellW, height: cellH)          // full-cell hit target
        .contentShape(Rectangle())
        .onTapGesture { grid.cycle(col: col, row: row) }
    }

    private func color(for type: HoldType?) -> Color {
        switch type {
        case .start: return .green
        case .move:  return .blue
        case .end:   return .red
        case .none:  return Color(.secondarySystemBackground)
        }
    }

    private var buttonRow: some View {
        VStack(spacing: 8) {
            if let err = ble.lastSendError {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Clear") { grid.clear() }
                    .buttonStyle(.bordered)
                    .disabled(grid.isEmpty)
                Spacer()
                Button("Save preset") { showingSave = true }
                    .buttonStyle(.bordered)
                    .disabled(grid.isEmpty)
                Spacer()
                Button("Light it") { ble.send(grid.holds) }
                    .buttonStyle(.borderedProminent)
                    .disabled(grid.isEmpty || !ble.isReady)
            }
        }
    }
}

// MARK: - Presets

struct PresetsView: View {
    @ObservedObject var presets: PresetStore
    let onLoad: (Preset) -> Void

    var body: some View {
        NavigationStack {
            List {
                if presets.presets.isEmpty {
                    Text("No presets yet. Build a route on the Board tab and tap Save.")
                        .foregroundStyle(.secondary)
                }
                ForEach(presets.presets) { preset in
                    Button {
                        onLoad(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                            Text("\(preset.holds.count) holds · \(preset.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete(perform: presets.delete)
            }
            .navigationTitle("Presets")
        }
    }
}

// MARK: - Connect

struct ConnectView: View {
    @ObservedObject var ble: BLEManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text(ble.status.label)
                        Spacer()
                        if case .connected = ble.status {
                            Button("Disconnect") { ble.disconnect() }
                        }
                    }
                }
                Section("Devices") {
                    if ble.visibleDevices.isEmpty {
                        Text("Tap Scan to find your MoonBoard box.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(ble.visibleDevices) { device in
                        Button(device.name) { ble.connect(device) }
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Connect")
            .toolbar {
                Button("Scan") { ble.startScan() }
            }
        }
    }
}

#Preview {
    ContentView()
}
