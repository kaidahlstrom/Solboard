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

    /// Emission order in the command string. The box silently ignores payloads
    /// that aren't grouped S -> P -> E, so this is load-bearing, not cosmetic.
    var sortRank: Int {
        switch self {
        case .start: return 0
        case .move:  return 1
        case .end:   return 2
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

    // Board geometry - MoonBoard 2024 full-size board.
    static let columns = 11          // A ... K
    static let rows = 18             // 1 ... 18
    static var holdCount: Int { columns * rows }   // 198

    // MARK: Pure mapping - (column, row, holdType) -> command fragment

    /// LED position for a 0-based grid cell (col A=0..K=10, row 0..17 bottom-up).
    ///
    /// Confirmed on-wall: positions are 0-based, range 0-197, laid out SERPENTINE.
    /// Even column indices run bottom-up; odd column indices run top-down.
    /// (Initial recon missed the serpentine because A1/C15/K18 all sit in even
    /// columns, where both layouts agree.) Verified mappings: 0->A1, 17->A18,
    /// 50->C15, 58->D14, 67->D5, 197->K18. Out-of-range positions are silently
    /// ignored by the box.
    static func position(col: Int, row: Int) -> Int {
        let within = (col % 2 == 0) ? row : (rows - 1 - row)
        return col * rows + within
    }

    /// Single hold as its protocol fragment, e.g. `S5`, `P90`, `E198`.
    static func fragment(for hold: Hold) -> String {
        "\(hold.type.rawValue)\(position(col: hold.col, row: hold.row))"
    }

    /// Full command string for a route: `l#S5,P9,P13,E18#`.
    /// Holds MUST be grouped by type (all S, then P, then E) - the box silently
    /// ignores payloads that aren't. Within a type, sort by position ascending
    /// for a stable, reproducible payload.
    static func command(for holds: [Hold]) -> String {
        let fragments = holds
            .sorted { a, b in
                if a.type.sortRank != b.type.sortRank {
                    return a.type.sortRank < b.type.sortRank
                }
                return position(col: a.col, row: a.row) < position(col: b.col, row: b.row)
            }
            .map(fragment(for:))
        return "l#" + fragments.joined(separator: ",") + "#"
    }

    /// UTF-8 bytes to write to the UART RX characteristic.
    static func payload(for holds: [Hold]) -> Data {
        Data(command(for: holds).utf8)
    }

    // MARK: BLE identifiers - CONFIRMED on-site (nRF Connect). Board name "MoonBoard A".

    /// Nordic UART Service - confirmed standard NUS UUID.
    static let uartService = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    /// NUS RX characteristic - the central WRITES route commands here. Confirmed.
    static let uartRX = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"

    // MARK: Board image overlay calibration (gym-day tunable, one place)

    /// Fractions of the "board" image consumed by margin OUTSIDE the 11x18 hold
    /// grid - the border of the artwork before the first/last hold centers. Tune
    /// these four numbers so the overlaid hold cells land on the drawn holds.
    struct ImageInsets {
        var top: CGFloat
        var bottom: CGFloat
        var left: CGFloat
        var right: CGFloat
    }
    // Measured from the actual hold positions in the board artwork - do not tweak
    // by eye. The matrix is asymmetric in the image, hence the differing sides.
    // Re-measure and replace wholesale if the board image is ever swapped; the
    // DEBUG "Calibrate" toggle on the Board tab visualizes the fit.
    static let imageInsets = ImageInsets(top: 0.008, bottom: 0.002, left: 0.022, right: 0.042)

    /// LED-dot rendering over the artwork, as fractions of a grid cell. The dot is
    /// drawn below each lit hold to mimic the under-hold LEDs on the real board.
    /// Calibrate against the artwork with the DEBUG "Calibrate" toggle.
    static let ledDotSize: CGFloat = 0.175     // diameter, in cell widths/heights
    static let ledDotOffset: CGFloat = 0.50    // downward shift below hold center, in cell heights (~ midway to the hold below)

    // Grid labels for the UI.
    static func columnLabel(_ col: Int) -> String {
        String(UnicodeScalar(UInt8(65 + col)))   // A ... K
    }
    static func rowLabel(_ row: Int) -> String {
        String(row + 1)                            // 1 ... 18
    }
}
