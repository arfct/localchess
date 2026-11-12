// BoardView.swift — LocalChess
// The board: deep-teal squares, gold last-move tint, legal-move dots,
// sliding pieces, capture pop, check pulse + king shake.
//
// Touch is one gesture over the whole board, so tap-tap and drag-and-drop
// share a single path:
//   - Touching your own piece picks it up (it lifts and its moves show).
//   - Drag it and it follows your finger from where you grabbed it, raised a
//     little so your finger doesn't hide it; the square it would land on is
//     ringed. Let go on a legal square to move, anywhere else and it slides
//     home.
//   - Or tap a piece, then tap where it should go. Tap it again to put it down.
// A piece's scale is applied before its position, so lifting a piece grows
// it in place (scaling after .position scales about the board's centre, which
// is what used to throw picked-up pieces sideways).

import SwiftUI

// Palette (original values).
enum BoardTheme {
    static let background = Color(red: 0.07, green: 0.11, blue: 0.13)
    static let panel = Color.white.opacity(0.05)
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

/// A piece being dragged: where it came from and how far the finger has
/// moved since touching it.
private struct Drag: Equatable {
    var from: Int
    var translation: CGSize
}

struct BoardView: View {
    @ObservedObject var game: GameState
    /// Turn Black's pieces to face the far side of the table, for two
    /// people sitting across a phone lying flat.
    var faceToFace = false
    var showCoordinates = true

    @State private var drag: Drag?
    /// The square the current touch began on, and whether that touch is
    /// what selected it (so lifting the finger doesn't put it straight down).
    @State private var press: (square: Int, pickedUp: Bool)?

    private var orientation: BoardOrientation { BoardOrientation(flipped: game.flipped) }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let sq = size / 8
            ZStack(alignment: .topLeading) {
                squares(sq)
                markers(sq)
                pieces(sq)
                if let mv = game.pendingPromotion {
                    PromotionPicker(game: game, move: mv, squareSize: sq, orientation: orientation,
                                    faceToFace: faceToFace)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .gesture(touch(sq))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("board")
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: Layers

    private func squares(_ sq: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { col in
                        let bsq = orientation.toBoard(displayCol: col, displayRow: row)
                        let light = (Square.file(of: bsq) + Square.rank(of: bsq)) % 2 == 1
                        Rectangle()
                            .fill(light ? BoardTheme.lightSquare : BoardTheme.darkSquare)
                            .overlay(highlight(bsq))
                            .overlay(alignment: .bottomTrailing) {
                                if showCoordinates && row == 7 { coord(fileName(bsq), light: light, sq: sq) }
                            }
                            .overlay(alignment: .topLeading) {
                                if showCoordinates && col == 0 { coord(String(Square.rank(of: bsq) + 1), light: light, sq: sq) }
                            }
                            .frame(width: sq, height: sq)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("square \(Square.name(of: bsq))")
                            .accessibilityIdentifier("sq-\(Square.name(of: bsq))")
                            .accessibilityValue(squareValue(bsq))
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
    }

    private func coord(_ s: String, light: Bool, sq: CGFloat) -> some View {
        Text(s)
            .font(.system(size: max(8, sq * 0.17), weight: .bold, design: .rounded))
            .foregroundColor((light ? BoardTheme.darkSquare : BoardTheme.lightSquare).opacity(0.9))
            .padding(.horizontal, sq * 0.06)
            .padding(.vertical, sq * 0.03)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func fileName(_ bsq: Int) -> String { String(Square.name(of: bsq).prefix(1)) }

    @ViewBuilder
    private func highlight(_ bsq: Int) -> some View {
        if game.selected == bsq {
            BoardTheme.selected
        } else if let last = game.board.lastMove, last.from == bsq || last.to == bsq {
            BoardTheme.lastMove
        } else {
            Color.clear
        }
    }

    /// Unique move targets for the selected piece (promotions share one).
    private var targets: [(square: Int, capture: Bool)] {
        var seen = Set<Int>()
        return game.legalTargets.compactMap { mv in
            seen.insert(mv.to).inserted ? (mv.to, mv.isCapture) : nil
        }
    }

    private func markers(_ sq: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(targets, id: \.square) { t in
                let name = Square.name(of: t.square)
                Group {
                    if t.capture {
                        Circle()
                            .stroke(Color.white.opacity(0.75), lineWidth: max(3, sq * 0.06))
                            .frame(width: sq * 0.92, height: sq * 0.92)
                            .accessibilityIdentifier("ring-\(name)")
                    } else {
                        Circle()
                            .fill(BoardTheme.dot)
                            .frame(width: sq * 0.30, height: sq * 0.30)
                            .accessibilityIdentifier("dot-\(name)")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(t.capture ? "capture" : "move") \(name)")
                .position(center(t.square, sq))
                .transition(.opacity)
            }
            if let ksq = checkedKing {
                CheckGlow(squareSize: sq)
                    .frame(width: sq, height: sq)
                    .position(center(ksq, sq))
            }
            // Where the dragged piece would land.
            if let d = drag, let over = square(at: dragCenter(d, sq), sq), over != d.from {
                let legal = game.legalTargets.contains { $0.to == over }
                RoundedRectangle(cornerRadius: sq * 0.08)
                    .stroke(legal ? Color.white.opacity(0.9) : Color.white.opacity(0.25),
                            lineWidth: max(2.5, sq * 0.06))
                    .background(RoundedRectangle(cornerRadius: sq * 0.08)
                        .fill(Color.white.opacity(legal ? 0.12 : 0)))
                    .frame(width: sq, height: sq)
                    .position(center(over, sq))
            }
        }
        .allowsHitTesting(false)
    }

    private func pieces(_ sq: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(placed) { item in
                let dragging = drag?.from == item.square
                let lifted = dragging || game.selected == item.square
                PieceArt(piece: item.piece)
                    .frame(width: sq * 0.9, height: sq * 0.9)
                    .rotationEffect(.degrees(faceToFace && item.piece.color == .black ? 180 : 0))
                    // Scale first, then place: the piece grows where it stands.
                    .scaleEffect(dragging ? 1.3 : (lifted ? 1.1 : 1))
                    .shadow(color: .black.opacity(dragging ? 0.45 : 0), radius: dragging ? 8 : 0,
                            y: dragging ? 6 : 0)
                    .offset(y: dragging ? -lift(sq) : 0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.7), value: lifted)
                    .animation(.spring(response: 0.18, dampingFraction: 0.8), value: dragging)
                    .position(dragging ? dragPoint(drag!, sq) : center(item.square, sq))
                    .zIndex(dragging ? 10 : (lifted ? 3 : (checkedKing == item.square ? 2 : 1)))
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Touch

    private func touch(_ sq: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                guard let start = square(at: v.startLocation, sq) else { return }
                if press == nil {
                    // Touch down. Picking up your own piece happens now, so
                    // its moves show before the finger moves.
                    if game.pendingPromotion != nil { return }
                    let had = game.selected == start
                    if game.canPickUp(start) && !had && !isTarget(start) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { game.select(start) }
                    }
                    press = (start, !had && game.selected == start)
                }
                let moved = hypot(v.translation.width, v.translation.height)
                if drag == nil, moved > 6, game.canPickUp(start), game.selected == start {
                    drag = Drag(from: start, translation: v.translation)
                } else if drag != nil {
                    // Follow the finger exactly: no animation while dragging.
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { drag?.translation = v.translation }
                }
            }
            .onEnded { v in
                defer { press = nil }
                if let d = drag {
                    let to = square(at: dragCenter(d, sq), sq)
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        drag = nil
                        if let to, to != d.from, !game.move(from: d.from, to: to) {
                            HapticManager.shared.illegal()
                        }
                    }
                    return
                }
                guard let p = press else { return }
                // A tap. The touch that picked a piece up is done already.
                if p.pickedUp { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { game.tap(square: p.square) }
            }
    }

    private func isTarget(_ bsq: Int) -> Bool {
        game.selected != nil && game.legalTargets.contains { $0.to == bsq }
    }

    /// How far a dragged piece rides above the finger.
    private func lift(_ sq: CGFloat) -> CGFloat { sq * 0.35 }

    private func dragPoint(_ d: Drag, _ sq: CGFloat) -> CGPoint {
        let c = center(d.from, sq)
        return CGPoint(x: c.x + d.translation.width, y: c.y + d.translation.height)
    }

    /// Where the dragged piece appears, which is where it lands.
    private func dragCenter(_ d: Drag, _ sq: CGFloat) -> CGPoint {
        let p = dragPoint(d, sq)
        return CGPoint(x: p.x, y: p.y - lift(sq))
    }

    // MARK: Geometry

    private func center(_ bsq: Int, _ sq: CGFloat) -> CGPoint {
        let (c, r) = orientation.toDisplay(boardSquare: bsq)
        return CGPoint(x: (CGFloat(c) + 0.5) * sq, y: (CGFloat(r) + 0.5) * sq)
    }

    private func square(at p: CGPoint, _ sq: CGFloat) -> Int? {
        let c = Int((p.x / sq).rounded(.down)), r = Int((p.y / sq).rounded(.down))
        guard (0..<8).contains(c), (0..<8).contains(r) else { return nil }
        return orientation.toBoard(displayCol: c, displayRow: r)
    }

    private var placed: [PlacedPiece] {
        (0..<64).compactMap { sq in game.board.squares[sq].map { PlacedPiece(piece: $0, square: sq) } }
    }

    private var checkedKing: Int? {
        game.board.isInCheck(game.board.turn) ? game.board.kingSquare(of: game.board.turn) : nil
    }

    private func squareValue(_ bsq: Int) -> String {
        var parts: [String] = []
        if game.selected == bsq { parts.append("selected") }
        if let p = game.board.squares[bsq] {
            parts.append("\(p.color == .white ? "white" : "black") \(p.type)")
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Promotion

/// The four pieces a pawn can become, stacked down from the promotion square
/// toward the middle of the board, like a menu opening from the pawn.
private struct PromotionPicker: View {
    @ObservedObject var game: GameState
    let move: ChessMove
    let squareSize: CGFloat
    let orientation: BoardOrientation
    let faceToFace: Bool

    var body: some View {
        let sq = squareSize
        let (col, row) = orientation.toDisplay(boardSquare: move.to)
        let down = row == 0
        let color = game.board.squares[move.from]?.color ?? game.board.turn
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.45)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.spring(response: 0.25)) { game.cancelPromotion() } }
                .accessibilityIdentifier("promotionCancel")
            ForEach(Array([PieceType.queen, .knight, .rook, .bishop].enumerated()), id: \.element) { i, t in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { game.confirmPromotion(t) }
                } label: {
                    PieceArt(piece: BoardPiece(color: color, type: t))
                        .padding(sq * 0.08)
                        .rotationEffect(.degrees(faceToFace && color == .black ? 180 : 0))
                        .frame(width: sq, height: sq)
                        .background(Circle().fill(Color.white.opacity(i == 0 ? 0.95 : 0.8)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("promote to \(t)")
                .accessibilityIdentifier("promote-\(t)")
                .position(x: (CGFloat(col) + 0.5) * sq,
                          y: (CGFloat(down ? row + i : row - i) + 0.5) * sq)
            }
        }
        .frame(width: sq * 8, height: sq * 8)
        .transition(.opacity)
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
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 8
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
                                    PieceArt(piece: p).padding(s * 0.06)
                                }
                            }
                            .frame(width: s, height: s)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
