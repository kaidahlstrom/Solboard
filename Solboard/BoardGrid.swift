//
//  BoardGrid.swift
//  Solboard
//
//  The current route being edited on screen. A plain value type: a sparse map of
//  grid cell -> HoldType. Lit holds only; empty cells are absent.
//

import Foundation

struct BoardGrid: Equatable {
    /// Key is (col, row), both 0-based. Absent = unlit.
    private var cells: [Cell: HoldType] = [:]

    struct Cell: Hashable {
        let col: Int
        let row: Int
    }

    func type(col: Int, row: Int) -> HoldType? {
        cells[Cell(col: col, row: row)]
    }

    /// Cycle a cell: none -> start -> move -> end -> none.
    mutating func cycle(col: Int, row: Int) {
        let key = Cell(col: col, row: row)
        switch cells[key] {
        case .none:        cells[key] = .start
        case .some(let t): cells[key] = t.next   // nil clears the cell
        }
    }

    mutating func clear() {
        cells.removeAll()
    }

    var isEmpty: Bool { cells.isEmpty }

    /// Flatten to the list form used for sending and for preset storage.
    var holds: [Hold] {
        cells.map { Hold(col: $0.key.col, row: $0.key.row, type: $0.value) }
    }

    init() { /* Explicit empty init: init(holds:) suppresses the implicit one */ }

    init(holds: [Hold]) {
        for h in holds {
            cells[Cell(col: h.col, row: h.row)] = h.type
        }
    }
}
