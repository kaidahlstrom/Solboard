//
//  ContentView.swift
//  Solboard
//
//  Three screens: Board (edit + light a route), Presets, Connect. Stock SwiftUI.
//

import SwiftUI

struct ContentView: View {
    // The route currently on the grid — shared so presets can load into it.
    @State private var grid = BoardGrid()
    @StateObject private var ble = BLEManager()
    @StateObject private var presets = PresetStore()

    var body: some View {
        TabView {
            BoardView(grid: $grid, ble: ble) { name in
                presets.add(name: name, holds: grid.holds)
            }
            .tabItem { Label("Board", systemImage: "square.grid.3x3") }

            PresetsView(presets: presets) { preset in
                grid = BoardGrid(holds: preset.holds)
            }
            .tabItem { Label("Presets", systemImage: "list.bullet") }

            ConnectView(ble: ble)
                .tabItem { Label("Connect", systemImage: "dot.radiowaves.left.and.right") }
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

    var body: some View {
        VStack(spacing: 12) {
            statusBar

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

            buttonRow
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

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(ble.isReady ? .green : .secondary)
                .frame(width: 10, height: 10)
            Text(ble.status.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
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
                    if ble.discovered.isEmpty {
                        Text("Tap Scan to find your MoonBoard box.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(ble.discovered) { device in
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
