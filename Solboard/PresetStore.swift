//
//  PresetStore.swift
//  Solboard
//
//  Presets persisted as a single JSON file in the app's Documents directory.
//  No SwiftData/CoreData, no networking. Schema per CLAUDE.md.
//

import Foundation
import Combine
import SwiftUI

struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var createdAt: Date
    var holds: [Hold]
}

@MainActor
final class PresetStore: ObservableObject {
    @Published private(set) var presets: [Preset] = []

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("presets.json")
    }()

    init() {
        load()
    }

    func add(name: String, holds: [Hold]) {
        let preset = Preset(name: name, createdAt: Date(), holds: holds)
        presets.insert(preset, at: 0)
        save()
    }

    func delete(at offsets: IndexSet) {
        presets.remove(atOffsets: offsets)
        save()
    }

    func rename(_ preset: Preset, to name: String) {
        guard let i = presets.firstIndex(of: preset) else { return }
        presets[i].name = name
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
