// BoardOrientation.swift — LocalChess
// Pure display<->board coordinate mapping (no UI), so it can be unit-tested
// headlessly. Display space: col 0 = left, row 0 = top.
// Unflipped (play as White): White home rank at the bottom.
// Flipped (play as Black): Black home rank at the bottom.

import Foundation

struct BoardOrientation {
    var flipped: Bool = false

    func toBoard(displayCol dc: Int, displayRow dr: Int) -> Int {
        if flipped {
            // 180-degree rotation: Black home rank at the bottom, h-file left.
            return Square.make(file: 7 - dc, rank: dr)
        } else {
            return Square.make(file: dc, rank: 7 - dr)
        }
    }

    func toDisplay(boardSquare bsq: Int) -> (col: Int, row: Int) {
        let f = Square.file(of: bsq), r = Square.rank(of: bsq)
        if flipped {
            return (7 - f, r)
        } else {
            return (f, 7 - r)
        }
    }
}
