// ReviewView.swift — LocalChess
// Post-game review room: yeti score, graded move list, scrub replay board
// with best-move arrows, stepper + autoplay, and tier quips.

import SwiftUI

struct ReviewView: View {
    @ObservedObject var game: GameState
    @Environment(\.dismiss) var dismiss
    /// Position index into review.positions (0 = start).
    @State private var selectedPly: Int = 0
    @State private var autoPlaying = false
    @State private var autoTask: Task<Void, Never>?

    private var review: GameReview? { game.review }

    var body: some View {
        ZStack {
            BoardTheme.background.ignoresSafeArea()
            if game.reviewing || review == nil {
                analyzingView
            } else {
                reviewBody(review: review!)
            }
        }
        .onAppear {
            NSLog("[LocalChess] review view appeared")
            game.startReview()
        }
        .onDisappear {
            autoTask?.cancel()
            autoPlaying = false
        }
    }

    // MARK: Analyzing

    private var analyzingView: some View {
        VStack(spacing: 18) {
            Spacer()
            YetiPortrait(asset: "yeti-thinking", label: "yeti studying")
                .frame(width: 120, height: 120)
                .shadow(color: BoardTheme.neonGreen.opacity(0.25), radius: 24)
            Text("READING THE SNOW")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundColor(BoardTheme.neonGreen)
            Text("Sniffing out blunders…")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(.white)
            ProgressView(value: game.reviewProgress)
                .tint(BoardTheme.neonGreen)
                .frame(maxWidth: 220)
            Text("Move \(Int(game.reviewProgress * Double(max(1, game.moveCount + 1)))) of \(game.moveCount + 1)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
                .monospacedDigit()
            Button("Cancel") {
                game.cancelReview()
                dismiss()
            }
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundColor(.gray)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: Review body

    private func reviewBody(review: GameReview) -> some View {
        let graded: [ReviewedMove] = game.vsEngine
            ? review.moves.filter { $0.mover == game.playerColor }
            : review.moves
        return VStack(spacing: 10) {
            headerRow
            scoreHero(graded: graded)
            ReplayBoard(game: game, review: review, selectedPly: clampedPly(review: review))
                .padding(.horizontal, 16)
            quipLine(review: review)
            moveList(review: review)
            controlsRow(review: review)
        }
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private func clampedPly(review: GameReview) -> Int {
        min(max(0, selectedPly), review.positions.count - 1)
    }

    private var headerRow: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.gray)
                    .frame(width: 34, height: 34)
            }
            .accessibilityIdentifier("review-close")
            Spacer()
            Text("GAME REVIEW")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundColor(.gray)
            Spacer()
            Button("Rematch") {
                game.newGame(as: game.playerSide, vsEngine: game.vsEngine,
                             difficulty: game.difficulty)
                dismiss()
            }
            .font(.system(size: 13, weight: .black, design: .rounded))
            .tracking(1)
            .foregroundColor(BoardTheme.neonGreen)
        }
        .padding(.horizontal, 16)
    }

    private func scoreHero(graded: [ReviewedMove]) -> some View {
        let best = graded.filter { $0.tier == .best }.count
        let dub = graded.filter { $0.tier == .dubious }.count
        let miss = graded.filter { $0.tier == .miss }.count
        let blun = graded.filter { $0.tier == .blunder }.count
        return HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text("\(review?.accuracy ?? 0)")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .accessibilityIdentifier("yeti-score")
                Text("YETI SCORE")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(2.5)
                    .foregroundColor(BoardTheme.neonGreen)
            }
            VStack(alignment: .leading, spacing: 6) {
                countRow("\(best) Best", color: BoardTheme.neonGreen)
                countRow("\(dub) Dubious", color: .yellow)
                countRow("\(miss) Misses", color: .orange)
                countRow("\(blun) Blunders", color: .red)
            }
        }
        .padding(.vertical, 4)
    }

    private func countRow(_ text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }

    private func quipLine(review: GameReview) -> some View {
        let ply = clampedPly(review: review)
        let text: String
        if ply == 0 || review.moves.isEmpty {
            text = "Scrub through your game below."
        } else {
            let mv = review.moves[min(ply - 1, review.moves.count - 1)]
            var t = MoveTier.quip(for: mv.tier)
            if let loss = mv.loss, loss >= 60 {
                t += " (−\(String(format: "%.1f", Double(loss) / 100.0)))"
            }
            text = "\(mv.san): \(t)"
        }
        return Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundColor(.white.opacity(0.9))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
    }

    private func moveList(review: GameReview) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(0..<review.moves.count / 2 + review.moves.count % 2, id: \.self) { row in
                    HStack(spacing: 8) {
                        Text("\(row + 1).")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundColor(.gray)
                            .frame(width: 30, alignment: .trailing)
                        moveCell(review: review, ply: row * 2)
                        if row * 2 + 1 < review.moves.count {
                            moveCell(review: review, ply: row * 2 + 1)
                        } else {
                            Spacer().frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func moveCell(review: GameReview, ply: Int) -> some View {
        let mv = review.moves[ply]
        let selected = clampedPly(review: review) == ply + 1
        return Button {
            selectedPly = ply + 1
            autoTask?.cancel()
            autoPlaying = false
            HapticManager.shared.select()
        } label: {
            HStack(spacing: 6) {
                Text(mv.san)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                if let label = mv.tier.label {
                    Text(mv.tier == .best ? label : (mv.tier.glyph ?? label))
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundColor(tierColor(mv.tier))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(tierColor(mv.tier).opacity(0.16))
                        )
                        .accessibilityIdentifier("tier-\(label)-\(ply)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? BoardTheme.neonGreen : Color.clear, lineWidth: 1.5)
            )
        }
        .accessibilityIdentifier("review-move-\(ply)")
        .buttonStyle(.plain)
    }

    private func tierColor(_ tier: MoveTier) -> Color {
        switch tier {
        case .best: return BoardTheme.neonGreen
        case .good, .unknown: return .gray
        case .dubious: return .yellow
        case .miss: return .orange
        case .blunder: return .red
        }
    }

    private func controlsRow(review: GameReview) -> some View {
        let maxPly = review.positions.count - 1
        return HStack(spacing: 18) {
            CircleButton(icon: "backward.end.fill") {
                selectedPly = 0
                autoTask?.cancel(); autoPlaying = false
                HapticManager.shared.select()
            }
            CircleButton(icon: "chevron.left") {
                selectedPly = max(0, clampedPly(review: review) - 1)
                autoTask?.cancel(); autoPlaying = false
                HapticManager.shared.select()
            }
            Button {
                togglePlay(maxPly: maxPly)
            } label: {
                Image(systemName: autoPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.17))
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(BoardTheme.neonGreen))
            }
            .accessibilityIdentifier("review-play")
            CircleButton(icon: "chevron.right") {
                selectedPly = min(maxPly, clampedPly(review: review) + 1)
                autoTask?.cancel(); autoPlaying = false
                HapticManager.shared.select()
            }
            CircleButton(icon: "forward.end.fill") {
                selectedPly = maxPly
                autoTask?.cancel(); autoPlaying = false
                HapticManager.shared.select()
            }
            Text("\(clampedPly(review: review)) / \(maxPly)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.gray)
                .monospacedDigit()
                .frame(width: 64)
        }
    }

    private func togglePlay(maxPly: Int) {
        if autoPlaying {
            autoTask?.cancel()
            autoPlaying = false
            return
        }
        if clampedPly(review: review!) >= maxPly { selectedPly = 0 }
        autoPlaying = true
        HapticManager.shared.select()
        autoTask = Task { [weak game] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak game] in
                    guard game != nil else { return }
                    if self.selectedPly >= maxPly {
                        self.autoTask?.cancel()
                        self.autoPlaying = false
                    } else {
                        self.selectedPly += 1
                        HapticManager.shared.select()
                    }
                }
            }
        }
    }
}

// MARK: - Replay board

/// Static position viewer with last-move tint and best-move arrow.
struct ReplayBoard: View {
    @ObservedObject var game: GameState
    let review: GameReview
    let selectedPly: Int

    private var orientation: BoardOrientation {
        BoardOrientation(flipped: game.flipped)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let sq = size / 8
            let squares = review.positions[selectedPly]
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { dr in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { dc in
                                let bsq = orientation.toBoard(displayCol: dc, displayRow: dr)
                                let isLight = (Square.file(of: bsq) + Square.rank(of: bsq)) % 2 == 1
                                ZStack {
                                    Rectangle()
                                        .fill(isLight ? BoardTheme.lightSquare : BoardTheme.darkSquare)
                                    if isLastMoveSquare(bsq) { BoardTheme.lastMove }
                                    if let p = squares[bsq] {
                                        PieceArt(piece: p)
                                            .frame(width: sq * 0.9, height: sq * 0.9)
                                    }
                                }
                                .frame(width: sq, height: sq)
                            }
                        }
                    }
                }
                if let arrow = bestArrow(squareSize: sq) {
                    ArrowShape(from: arrow.0, to: arrow.1)
                        .fill(Color(red: 0.35, green: 0.80, blue: 0.02).opacity(0.75))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedPly)
    }

    private func isLastMoveSquare(_ bsq: Int) -> Bool {
        guard selectedPly > 0, selectedPly - 1 < review.moves.count else { return false }
        guard let (from, to) = uciSquares(review.moves[selectedPly - 1].uci) else { return false }
        return bsq == from || bsq == to
    }

    /// Best-move arrow for the move that led here (when it differs).
    private func bestArrow(squareSize sq: CGFloat) -> (CGPoint, CGPoint)? {
        guard selectedPly > 0, selectedPly - 1 < review.moves.count else { return nil }
        let mv = review.moves[selectedPly - 1]
        guard let best = mv.bestUci, best != mv.uci,
              mv.tier == .blunder || mv.tier == .miss || mv.tier == .dubious,
              let (from, to) = uciSquares(best) else { return nil }
        return (center(of: from, squareSize: sq), center(of: to, squareSize: sq))
    }

    private func center(of bsq: Int, squareSize sq: CGFloat) -> CGPoint {
        let (dc, dr) = orientation.toDisplay(boardSquare: bsq)
        return CGPoint(x: (CGFloat(dc) + 0.5) * sq, y: (CGFloat(dr) + 0.5) * sq)
    }

    private func uciSquares(_ uci: String) -> (Int, Int)? {
        let files = Array("abcdefgh")
        let c = Array(uci.lowercased())
        guard c.count >= 4,
              let ff = files.firstIndex(of: c[0]),
              let tf = files.firstIndex(of: c[2]),
              let fr = c[1].wholeNumberValue, let tr = c[3].wholeNumberValue,
              (1...8).contains(fr), (1...8).contains(tr) else { return nil }
        return (Square.make(file: ff, rank: fr - 1), Square.make(file: tf, rank: tr - 1))
    }
}

/// Tapered arrow with a round tail and triangular head.
struct ArrowShape: Shape {
    let from: CGPoint
    let to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = to.x - from.x, dy = to.y - from.y
        let len = max(1, hypot(dx, dy))
        let ux = dx / len, uy = dy / len
        let tailR = min(11, len * 0.12)
        let headLen = min(26, len * 0.35)
        let headW = headLen * 0.55
        // Tail dot.
        path.addEllipse(in: CGRect(x: from.x - tailR, y: from.y - tailR,
                                   width: tailR * 2, height: tailR * 2))
        // Shaft (tapers into the head base).
        let bx = to.x - ux * headLen, by = to.y - uy * headLen
        let px = -uy, py = ux
        let w0 = tailR * 0.8, w1 = headW * 0.5
        path.move(to: CGPoint(x: from.x + px * w0, y: from.y + py * w0))
        path.addLine(to: CGPoint(x: bx + px * w1, y: by + py * w1))
        path.addLine(to: CGPoint(x: bx - px * w1, y: by - py * w1))
        path.addLine(to: CGPoint(x: from.x - px * w0, y: from.y - py * w0))
        path.closeSubpath()
        // Head triangle.
        path.move(to: to)
        path.addLine(to: CGPoint(x: bx + px * headW, y: by + py * headW))
        path.addLine(to: CGPoint(x: bx - px * headW, y: by - py * headW))
        path.closeSubpath()
        return path
    }
}
