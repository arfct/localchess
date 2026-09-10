// PieceArt.swift — LocalChess
// Professional piece artwork: the Cburnett set by Colin M.L. Burnett
// (Wikimedia Commons, multi-licensed GFDL / BSD / GPL — used here under the
// BSD license; see README Credits), bundled as vectors so the game stays
// fully offline and crisp at every size.

import SwiftUI

struct PieceArt: View {
    let piece: BoardPiece

    var body: some View {
        Image(imageName(for: piece))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 2)
    }

    private func imageName(for piece: BoardPiece) -> String {
        let color = piece.color == .white ? "w" : "b"
        let kind: String
        switch piece.type {
        case .pawn: kind = "p"
        case .knight: kind = "n"
        case .bishop: kind = "b"
        case .rook: kind = "r"
        case .queen: kind = "q"
        case .king: kind = "k"
        }
        return color + kind
    }
}
