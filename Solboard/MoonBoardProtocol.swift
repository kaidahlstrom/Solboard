//
//  MoonBoardProtocol.swift
//  Solboard
//
//  The ONLY place that knows how the physical board is wired. Everything the
//  gym-day investigation might change (0/1-basing, serpentine direction, command
//  framing) lives here as named constants and one pure mapping function, so the
//  fixes touch a single file. See CLAUDE.md "Protocol" + "Verification plan".
//

import Foundation

// MARK: - Model

/// A hold's role in a route. The raw value IS the protocol type character.
enum HoldType: String, Codable, CaseIterable, Identifiable {
    case start = "S"   // green
    case move  = "P"   // blue  (progress)
    case end   = "E"   // red

    var id: String { rawValue }

    /// none -> start -> move -> end -> none, for tap cycling on the grid.
    var next: HoldType? {
        switch self {
        case .start: return .move
        case .move:  return .end
        case .end:   return nil
        }
    }
}

/// One lit hold. `col` is 0-based (A=0 ... K=10); `row` is 0-based bottom-up
/// (row label "1" = 0 ... row label "18" = 17). Stored this way in preset JSON.
struct Hold: Codable, Equatable {
    var col: Int
    var row: Int
    var type: HoldType
}

// MARK: - Protocol

enum MoonBoardProtocol {

    // Board geometry — MoonBoard 2024 full-size board.
    static let columns = 11          // A ... K
    static let rows = 18             // 1 ... 18
    static var holdCount: Int { columns * rows }   // 198

    // ---- Gym-day tunables (Q2/Q3 in CLAUDE.md). Flip after the test pattern. ----

    /// Q2: community sources conflict. e-sr docs say positions run 1–198;
    /// some Arduino builds index A1 = 0. Set false if the box is 0-based.
    static let positionsAreOneBased = true

    /// Q3: the LED strip runs serpentine up the columns. `true` means column A
    /// (the first column) counts upward with the row numbers; adjacent columns
    /// alternate direction. Flip if the lit holds come out vertically mirrored.
    static let firstColumnRunsUpward = true

    /// If the strip physically starts at column K instead of A, set false so the
    /// position count begins from the right. Flip if columns come out mirrored.
    static let firstColumnIsA = true

    // MARK: Pure mapping — (column, row, holdType) -> command fragment

    /// LED position (respecting `positionsAreOneBased`) for a 0-based grid cell.
    /// Serpentine: consecutive columns run in opposite vertical directions.
    static func position(col: Int, row: Int) -> Int {
        let colIndex = firstColumnIsA ? col : (columns - 1 - col)
        // Even column index runs in the seed direction, odd runs reversed.
        let runsUpward = (colIndex % 2 == 0) == firstColumnRunsUpward
        let within = runsUpward ? row : (rows - 1 - row)
        let zeroBased = colIndex * rows + within
        return positionsAreOneBased ? zeroBased + 1 : zeroBased
    }

    /// Single hold as its protocol fragment, e.g. `S5`, `P90`, `E198`.
    static func fragment(for hold: Hold) -> String {
        "\(hold.type.rawValue)\(position(col: hold.col, row: hold.row))"
    }

    /// Full command string for a route: `l#S5,P9,P13,E18#`.
    /// Holds are emitted in position order for a stable, reproducible payload.
    static func command(for holds: [Hold]) -> String {
        let fragments = holds
            .sorted { position(col: $0.col, row: $0.row) < position(col: $1.col, row: $1.row) }
            .map(fragment(for:))
        return "l#" + fragments.joined(separator: ",") + "#"
    }

    /// UTF-8 bytes to write to the UART TX characteristic.
    static func payload(for holds: [Hold]) -> Data {
        Data(command(for: holds).utf8)
    }

    // MARK: BLE identifiers (Q1) — CONFIRM AT THE GYM with nRF Connect, then set.

    /// Nordic UART Service. This is the standard NUS UUID; verify the box uses it.
    static let uartService = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    /// TX characteristic (write). Verify UUID + whether it's write-with-response.
    static let uartTX = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"

    // Grid labels for the UI.
    static func columnLabel(_ col: Int) -> String {
        String(UnicodeScalar(UInt8(65 + col)))   // A ... K
    }
    static func rowLabel(_ row: Int) -> String {
        String(row + 1)                            // 1 ... 18
    }
}
