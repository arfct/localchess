// GameLayout.swift — LocalChess
// Where things go on each screen, iPhone Duo first.
//
//   iPhone, Duo outside display   one column: coach, the yeti's strip, the
//                                 board, your strip, controls
//   Duo tabletop (folded flat     the board on the half lying flat, where it's
//   across the middle)            easy to reach; coach, clocks and moves on
//                                 the raised half
//   Duo book (folded down the     the board on one page, everything else on
//   spine)                        the other, never across the fold
//   Duo open flat, portrait       a big board; with two players, Black's strip
//                                 turned to face across the table, and Black's
//                                 pieces too
//   any wide screen               the board as tall as the screen, a panel
//                                 beside it
//
// The fold comes from SwiftUI's reservedRegions(kind: .division) on iOS
// 27.1+. Launch with `-LCFold tabletop` or `-LCFold book` to fake one, for
// trying the layouts without folding a phone.

import SwiftUI

enum Arrangement: Equatable {
    case compact
    case tall(faceToFace: Bool)
    case side
    case tabletop(CGRect)
    case book(CGRect)

    var isLarge: Bool { self != .compact }
}

enum Fold {
    /// The fold, in this view's coordinates, when the phone is partly folded.
    static func region(_ g: GeometryProxy) -> CGRect? {
        let bounds = CGRect(origin: .zero, size: g.size)
        if let fake = UserDefaults.standard.string(forKey: "LCFold") {
            switch fake {
            case "tabletop": return CGRect(x: 0, y: bounds.midY - 10, width: bounds.width, height: 20)
            case "book": return CGRect(x: bounds.midX - 10, y: 0, width: 20, height: bounds.height)
            default: break
            }
        }
        guard #available(iOS 27.1, *) else { return nil }
        guard let r = g.reservedRegions(kind: .division).first(where: \.isActive) else { return nil }
        var f = r.frame
        if !bounds.intersects(f) {
            let o = g.frame(in: .global).origin
            f = f.offsetBy(dx: -o.x, dy: -o.y)
        }
        let c = f.intersection(bounds)
        return c.isNull || c.isEmpty ? nil : c
    }

    static func arrangement(_ g: GeometryProxy, twoPlayer: Bool) -> Arrangement {
        let s = g.size
        if let f = region(g) {
            // Only when each side of the fold has room for a usable board.
            if f.width >= f.height, f.minY > 220, s.height - f.maxY > 280 { return .tabletop(f) }
            if f.height > f.width, f.minX > 240, s.width - f.maxX > 280 { return .book(f) }
        }
        if s.width > s.height * 1.25 { return .side }
        if min(s.width, s.height) >= 600 { return .tall(faceToFace: twoPlayer) }
        return .compact
    }
}

// MARK: - Player strip

/// One side of the game: who, what they've taken, their clock. Lit up when
/// it's their move.
struct PlayerStrip: View {
    @ObservedObject var game: GameState
    let color: PieceColor
    var large = false

    private var active: Bool { !game.isGameOver && game.board.turn == color }
    private var isYeti: Bool { game.vsEngine && color != game.playerColor }

    private var name: String {
        if game.vsEngine { return isYeti ? "Yeti · \(game.difficulty.title)" : "You" }
        return color == .white ? "White" : "Black"
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color == .white ? Color.white : Color.black)
                .frame(width: large ? 18 : 14, height: large ? 18 : 14)
                .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: large ? 17 : 15, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                CapturedRow(game: game, color: color, size: large ? 18 : 15)
            }
            Spacer(minLength: 4)
            if isYeti && game.engineThinking {
                Text("Thinking…")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.gray)
                    .transition(.opacity)
            }
            if game.hasClock(color) {
                ClockPill(game: game, color: color, large: large)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, large ? 10 : 7)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(active ? 0.09 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(active ? BoardTheme.neonGreen.opacity(0.7) : Color.white.opacity(0.08),
                        lineWidth: active ? 2 : 1)
        )
        .animation(.easeOut(duration: 0.2), value: active)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("strip-\(color == .white ? "white" : "black")")
    }
}

struct ClockPill: View {
    @ObservedObject var game: GameState
    let color: PieceColor
    var large = false

    var body: some View {
        let running = game.runningClock == color
        let low = game.seconds(color) < 60
        Text(game.clockText(color))
            .font(.system(size: large ? 22 : 18, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundColor(running ? Color(red: 0.10, green: 0.15, blue: 0.17) : (low ? .red : .gray))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(running ? (low ? Color.red : BoardTheme.neonGreen) : Color.white.opacity(0.06))
            )
            .accessibilityIdentifier("clock-\(color == .white ? "white" : "black")")
    }
}

/// The pieces `color` has taken, and how far ahead on material it is.
struct CapturedRow: View {
    @ObservedObject var game: GameState
    let color: PieceColor
    var size: CGFloat = 16

    var body: some View {
        let taken = game.captured(by: color)
        let lead = game.materialLead(color)
        HStack(spacing: -size * 0.35) {
            ForEach(Array(taken.enumerated()), id: \.offset) { _, t in
                PieceArt(piece: BoardPiece(color: color.opposite, type: t))
                    .frame(width: size, height: size)
            }
            if lead > 0 {
                Text("+\(lead)")
                    .font(.system(size: size * 0.75, weight: .bold, design: .rounded))
                    .foregroundColor(.gray)
                    .padding(.leading, size * 0.5)
            }
        }
        .frame(height: size)
        .animation(.spring(response: 0.3), value: taken.count)
    }
}

// MARK: - Move list

/// The moves so far in SAN. `inline` is a strip that keeps the latest move
/// in view; otherwise numbered rows, white and black side by side.
struct MoveList: View {
    @ObservedObject var game: GameState
    var inline = false

    private var pairs: [(n: Int, white: String, black: String?)] {
        stride(from: 0, to: game.sanMoves.count, by: 2).map { i in
            (i / 2 + 1, game.sanMoves[i], i + 1 < game.sanMoves.count ? game.sanMoves[i + 1] : nil)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if inline {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            if pairs.isEmpty { placeholder }
                            ForEach(pairs, id: \.n) { p in
                                HStack(spacing: 5) {
                                    Text("\(p.n).").foregroundColor(.gray)
                                    Text(p.white).foregroundColor(.white)
                                    if let b = p.black { Text(b).foregroundColor(.white) }
                                }
                                .id(p.n)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if pairs.isEmpty { placeholder.padding(12) }
                            ForEach(pairs, id: \.n) { p in
                                HStack(spacing: 0) {
                                    Text("\(p.n).").foregroundColor(.gray).frame(width: 40, alignment: .leading)
                                    Text(p.white).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(p.black ?? "").foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(p.n % 2 == 0 ? Color.white.opacity(0.03) : Color.clear)
                                .id(p.n)
                            }
                        }
                    }
                }
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .onChange(of: game.sanMoves.count) { _ in
                withAnimation { proxy.scrollTo(pairs.last?.n, anchor: inline ? .trailing : .bottom) }
            }
        }
        .accessibilityIdentifier("moveList")
    }

    private var placeholder: some View {
        Text("Moves appear here")
            .foregroundColor(.gray.opacity(0.7))
    }
}
