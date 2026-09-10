// BoardView.swift — LocalChess
// Duolingo-vibe board: deep-teal squares, gold last-move tint, legal-move
// dots, sliding piece animations, capture pop, check pulse + king shake.

import SwiftUI

// Duolingo-style palette (original values, matched by eye to the reference).
enum BoardTheme {
    static let background = Color(red: 0.07, green: 0.11, blue: 0.13)
    static let lightSquare = Color(red: 0.24, green: 0.35, blue: 0.40)
    static let darkSquare = Color(red: 0.12, green: 0.19, blue: 0.22)
    static let lastMove = Color(red: 1.0, green: 0.78, blue: 0.0).opacity(0.38)
    static let selected = Color(red: 1.0, green: 0.85, blue: 0.25).opacity(0.55)
    static let dot = Color.white.opacity(0.35)
    static let neonGreen = Color(red: 0.35, green: 0.80, blue: 0.02)
}

private struct PlacedPiece: Identifiable {
    let piece: BoardPiece
    let square: Int
    var id: UUID { piece.id }
}

struct BoardView: View {
    @ObservedObject var game: GameState

    private var orientation: BoardOrientation {
        BoardOrientation(flipped: game.flipped)
    }

    /// Unique dot target squares (promotion quadruples share one target).
    private var dotTargets: [(square: Int, isCapture: Bool)] {
        var seen = Set<Int>()
        var out: [(Int, Bool)] = []
        for mv in game.legalTargets {
            if seen.insert(mv.to).inserted {
                out.append((mv.to, game.legalTargets.contains(where: { $0.to == mv.to && $0.isCapture })))
            }
        }
        return out
    }

    private var placed: [PlacedPiece] {
        var out: [PlacedPiece] = []
        for sq in 0..<64 {
            if let p = game.board.squares[sq] {
                out.append(PlacedPiece(piece: p, square: sq))
            }
        }
        return out
    }

    private var kingInCheckSquare: Int? {
        let turn = game.board.turn
        if game.board.isInCheck(turn) {
            return game.board.kingSquare(of: turn)
        }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let sq = size / 8
            ZStack {
                // Squares. Each cell handles its own taps, so input can never
                // drift from what is rendered (no gesture coordinate math).
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { displayRow in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { displayCol in
                                let bsq = orientation.toBoard(displayCol: displayCol, displayRow: displayRow)
                                let isLight = (Square.file(of: bsq) + Square.rank(of: bsq)) % 2 == 1
                                Rectangle()
                                    .fill(isLight ? BoardTheme.lightSquare : BoardTheme.darkSquare)
                                    .frame(width: sq, height: sq)
                                    .overlay(squareOverlay(for: bsq))
                                    .contentShape(Rectangle())
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("square \(Square.name(of: bsq))")
                                    .accessibilityIdentifier("sq-\(Square.name(of: bsq))")
                                    .accessibilityValue(squareValue(bsq))
                                    .onTapGesture {
                                        game.tap(square: bsq)
                                    }
                            }
                        }
                    }
                }

                // Legal-move dots (one marker per target square).
                ForEach(dotTargets, id: \.square) { target in
                    let d = displayOf(boardSquare: target.square, squareSize: sq, boardSize: size)
                    let name = Square.name(of: target.square)
                    if target.isCapture {
                        Circle()
                            .stroke(Color.white.opacity(0.75), lineWidth: max(3, sq * 0.06))
                            .frame(width: sq * 0.92, height: sq * 0.92)
                            .position(d)
                            .allowsHitTesting(false)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("capture \(name)")
                            .accessibilityIdentifier("ring-\(name)")
                    } else {
                        Circle()
                            .fill(BoardTheme.dot)
                            .frame(width: sq * 0.30, height: sq * 0.30)
                            .position(d)
                            .allowsHitTesting(false)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("move \(name)")
                            .accessibilityIdentifier("dot-\(name)")
                    }
                }

                // Check glow on the mated/checked king.
                if let ksq = kingInCheckSquare {
                    let d = displayOf(boardSquare: ksq, squareSize: sq, boardSize: size)
                    CheckGlow(squareSize: sq)
                        .frame(width: sq, height: sq)
                        .position(d)
                        .allowsHitTesting(false)
                }

                // Pieces (absolute positioning => moves animate as slides).
                ForEach(placed) { item in
                    let d = displayOf(boardSquare: item.square, squareSize: sq, boardSize: size)
                    PieceArt(piece: item.piece)
                        .frame(width: sq * 0.90, height: sq * 0.90)
                        .position(d)
                        .allowsHitTesting(false)
                        .scaleEffect(game.selected == item.square ? 1.12 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 1.0),
                                   value: item.square)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6),
                                   value: game.selected == item.square)
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                        .zIndex(game.selected == item.square ? 3 : (kingInCheckSquare == item.square ? 2 : 1))
                }
            }
            .frame(width: size, height: size)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("board")
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func squareOverlay(for bsq: Int) -> some View {
        if let last = game.board.lastMove, last.from == bsq || last.to == bsq {
            BoardTheme.lastMove
        } else if game.selected == bsq {
            BoardTheme.selected
        } else {
            Color.clear
        }
    }

    private func squareValue(_ bsq: Int) -> String {
        var parts: [String] = []
        if game.selected == bsq { parts.append("selected") }
        if let p = game.board.squares[bsq] {
            parts.append("\(p.color == .white ? "white" : "black") \(p.type)")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Orientation mapping (single source of truth)

    private func displayOf(boardSquare bsq: Int, squareSize sq: CGFloat, boardSize size: CGFloat) -> CGPoint {
        let (dc, dr) = orientation.toDisplay(boardSquare: bsq)
        return CGPoint(x: (CGFloat(dc) + 0.5) * sq, y: (CGFloat(dr) + 0.5) * sq)
    }
}

// MARK: - Check glow + shake

struct CheckGlow: View {
    let squareSize: CGFloat
    @State private var pulse = false
    @State private var shake = 0.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.red.opacity(pulse ? 0.55 : 0.30))
                .blur(radius: 2)
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.red.opacity(0.95), lineWidth: 3)
                .scaleEffect(pulse ? 1.04 : 0.96)
        }
        .offset(x: shake)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 0.07).repeatForever(autoreverses: true)) {
                shake = 3
            }
        }
    }
}

// MARK: - Mini board (checkmate card + share image)

struct MiniBoard: View {
    let snapshot: PositionSnapshot
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { col in
                        // Snapshot is always shown white-at-bottom.
                        let sq = Square.make(file: col, rank: 7 - row)
                        let isLight = (col + (7 - row)) % 2 == 1
                        ZStack {
                            Rectangle()
                                .fill(isLight ? Color(red: 0.94, green: 0.94, blue: 0.94)
                                              : Color(red: 0.80, green: 0.82, blue: 0.84))
                            if let p = snapshot.squares[sq] {
                                PieceArt(piece: p).padding(2)
                            }
                        }
                        .frame(width: 36, height: 36)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
