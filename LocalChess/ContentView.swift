// ContentView.swift — LocalChess
// Main screen mirroring the reference: timer + points pills, "Play Chess"
// title, coach + speech bubble, board, undo/redo, and the Checkmate! card.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var game: GameState
    @State private var showMenu = false
    @State private var showConfetti = false
    @State private var shareImage: UIImage?

    var body: some View {
        ZStack {
            BoardTheme.background.ignoresSafeArea()

            VStack(spacing: 10) {
                topBar
                titleRow
                CoachView(message: game.coachMessage, mood: game.coachMood)
                    .frame(height: 92)
                BoardView(game: game)
                    .padding(.horizontal, 12)
                statusRow
                Spacer(minLength: 8)
                bottomBar
            }
            .padding(.top, 8)

            if showConfetti { ConfettiView().allowsHitTesting(false) }

            if game.showMateModal {
                MateModal(
                    game: game,
                    onShowOff: {
                        showConfetti = true
                        HapticManager.shared.checkmate(playerWon: game.mateWon ?? true)
                        shareImage = renderShareImage()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            showConfetti = false
                        }
                    },
                    onContinue: { game.showMateModal = false }
                )
            }
        }
        .sheet(isPresented: $showMenu) { MenuSheet(game: game) }
        .sheet(isPresented: promotionBinding) { PromotionSheet(game: game) }
        .sheet(item: $shareImage) { img in ShareSheet(image: img) }
        .onChange(of: game.showMateModal) { visible in
            if visible && (game.mateWon ?? false) {
                showConfetti = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    showConfetti = false
                }
            }
        }
        .onAppear { HapticManager.shared.prepare() }
    }

    // MARK: Sections

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { showMenu = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.gray)
                    .frame(width: 30, height: 30)
            }
            .accessibilityIdentifier("menu")
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundColor(game.secondsLeft < 60 ? .red : .gray)
                    Text(game.clockText)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(game.secondsLeft < 60 ? .red : .gray)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                Divider().frame(height: 26)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(game.points < 0 ? .red : BoardTheme.neonGreen)
                    Text("\(game.points) POINTS")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .tracking(1)
                        .foregroundColor(game.points < 0 ? .red : BoardTheme.neonGreen)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
            )
        }
        .padding(.horizontal, 14)
    }

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("LOCALCHESS · OFFLINE")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundColor(BoardTheme.neonGreen)
            HStack {
                Text("Play Chess")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                if game.engineThinking {
                    Text("Thinking…")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(Color.white.opacity(0.08))
                                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
                        )
                }
            }
        }
        .padding(.horizontal, 18)
    }

    private var statusRow: some View {
        HStack {
            if game.board.isInCheck(game.board.turn) && !game.isGameOver {
                Text("CHECK!")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.red))
            } else if game.isGameOver {
                Text(gameOverText)
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(BoardTheme.neonGreen)
            } else {
                Text(turnText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.gray)
            }
            Spacer()
            Text(game.vsEngine ? "vs \(game.difficulty.title)" : "2 players · local")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundColor(.gray.opacity(0.8))
        }
        .padding(.horizontal, 20)
    }

    private var bottomBar: some View {
        HStack {
            CircleButton(icon: "arrow.uturn.backward") { game.undo() }
                .accessibilityIdentifier("undo")
                .opacity(game.canUndo ? 1 : 0.35)
                .disabled(!game.canUndo)
            Spacer()
            Button("NEW GAME") { showMenu = true }
                .font(.system(size: 14, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundColor(BoardTheme.neonGreen)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .stroke(BoardTheme.neonGreen.opacity(0.5), lineWidth: 1.5)
                )
            Spacer()
            CircleButton(icon: "arrow.uturn.forward") { game.redo() }
                .accessibilityIdentifier("redo")
                .opacity(game.canRedo ? 1 : 0.35)
                .disabled(!game.canRedo)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }

    private var turnText: String {
        if !game.vsEngine {
            return game.board.turn == .white ? "White to move" : "Black to move"
        }
        if game.board.turn == game.playerColor {
            return game.playerSide == .white ? "Your move — White" : "Your move — Black"
        }
        return "Yeti is thinking…"
    }

    private var gameOverText: String {
        switch game.status {
        case .checkmate(let winner):
            let you = !game.vsEngine ? true : (winner == game.playerColor)
            return you ? "Checkmate — you win!" : "Checkmate — yeti wins"
        case .stalemate: return "Stalemate — draw"
        case .draw(let reason): return "Draw — \(reason)"
        case .timeout(let winner):
            let you = !game.vsEngine ? true : (winner == game.playerColor)
            return you ? "Time — you win!" : "Time — yeti wins"
        case .ongoing: return ""
        }
    }

    private var promotionBinding: Binding<Bool> {
        Binding(
            get: { game.pendingPromotion != nil },
            set: { if !$0 { game.pendingPromotion = nil } }
        )
    }

    private func renderShareImage() -> UIImage? {
        let snap = game.board.snapshot()
        let view = MiniBoard(snapshot: snap).frame(width: 288, height: 288)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}

// MARK: - Buttons & sheets

struct CircleButton: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.gray)
                .frame(width: 56, height: 56)
                .background(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1.5))
        }
    }
}

// MARK: - New-match sheet
// Designed page, not a stock Form: yeti hero up top, chunky tappable
// cards, springy entrances, and a haptic tick on every switch.

struct MenuSheet: View {
    @ObservedObject var game: GameState
    @Environment(\.dismiss) var dismiss
    @State private var side: PlayerSide = .white
    @State private var difficulty: EngineDifficulty = .clever
    @State private var vsEngine = true
    @State private var appeared = false
    @State private var bob: CGFloat = 0
    @State private var greeting = CoachLines.opening.randomElement() ?? "Fresh snow!"

    /// The hero portrait reacts to the matchup: pick Beast and the
    /// crown comes out.
    private var heroAsset: String {
        guard vsEngine else { return "yeti-happy" }
        switch difficulty {
        case .chill: return "yeti-thinking"
        case .clever: return "yeti-happy"
        case .beast: return "yeti-excited"
        }
    }

    var body: some View {
        ZStack {
            BoardTheme.background.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    hero
                    sideCard
                    opponentCard
                    strengthCard
                    footnotes
                    startButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            side = game.playerSide
            difficulty = game.difficulty
            vsEngine = game.vsEngine
            greeting = CoachLines.opening.randomElement() ?? greeting
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                bob = -7
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 10) {
            YetiPortrait(asset: heroAsset, label: "yeti host")
                .frame(width: 132, height: 132)
                .shadow(color: BoardTheme.neonGreen.opacity(0.25), radius: 24)
                .offset(y: bob)
                .id(heroAsset)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.65), value: heroAsset)
            Text("LOCALCHESS · OFFLINE")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(3)
                .foregroundColor(BoardTheme.neonGreen)
            Text("New match")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(greeting)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .scaleEffect(appeared ? 1 : 0.8)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: Cards

    private var sideCard: some View {
        menuCard(title: "PICK YOUR ARMY", delay: 0.05) {
            HStack(spacing: 12) {
                sideTile(side: .white, title: "White", sub: "Moves first")
                sideTile(side: .black, title: "Black", sub: "Moves second")
            }
        }
    }

    private func sideTile(side: PlayerSide, title: String, sub: String) -> some View {
        let selected = self.side == side
        return Button {
            self.side = side
            HapticManager.shared.select()
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(side == .white ? Color.white : Color.black)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1.5))
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(BoardTheme.neonGreen)
                            .font(.system(size: 16, weight: .bold))
                            .offset(x: 20, y: -16)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text(sub)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(selected ? Color.white.opacity(0.10) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(selected ? BoardTheme.neonGreen : Color.white.opacity(0.14),
                            lineWidth: selected ? 2.5 : 1.5)
            )
            .shadow(color: selected ? BoardTheme.neonGreen.opacity(0.3) : .clear, radius: 12)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selected)
    }

    private var opponentCard: some View {
        menuCard(title: "WHO SITS ACROSS?", delay: 0.10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Battle the Yeti")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(vsEngine ? "Offline GNU Chess brain" : "A friend on this phone")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                }
                Spacer()
                Toggle("", isOn: $vsEngine)
                    .labelsHidden()
                    .tint(BoardTheme.neonGreen)
                    .accessibilityIdentifier("vsEngineToggle")
                    .onChange(of: vsEngine) { _ in HapticManager.shared.select() }
            }
        }
    }

    private var strengthCard: some View {
        menuCard(title: "HOW SPICY?", delay: 0.15) {
            HStack(spacing: 10) {
                ForEach(EngineDifficulty.allCases) { d in
                    strengthTile(d)
                }
            }
            .opacity(vsEngine ? 1 : 0.35)
            .disabled(!vsEngine)
        }
    }

    private func strengthTile(_ d: EngineDifficulty) -> some View {
        let selected = difficulty == d
        return Button {
            difficulty = d
            HapticManager.shared.select()
        } label: {
            VStack(spacing: 4) {
                Text(d.title.uppercased())
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(selected ? Color(red: 0.10, green: 0.15, blue: 0.17) : .white)
                Text(MenuSheet.spiceLine(d))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(selected ? Color(red: 0.10, green: 0.15, blue: 0.17).opacity(0.7) : .gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? BoardTheme.neonGreen : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? Color.clear : Color.white.opacity(0.14), lineWidth: 1.5)
            )
            .shadow(color: selected ? BoardTheme.neonGreen.opacity(0.35) : .clear, radius: 10)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selected)
    }

    private static func spiceLine(_ d: EngineDifficulty) -> String {
        switch d {
        case .chill: return "Snow cones"
        case .clever: return "Avalanche watch"
        case .beast: return "Full blizzard"
        }
    }

    private func menuCard<Content: View>(title: String, delay: Double,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .tracking(2)
                .foregroundColor(.gray)
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 26)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay), value: appeared)
    }

    private var footnotes: some View {
        VStack(spacing: 6) {
            Text(ArasanAdapter.shared.engineStatusText)
            Text("Engine: Arasan 26.0 by Jon Dart (MIT). Pieces: Cburnett set by Colin M.L. Burnett (Wikimedia Commons), BSD license.")
        }
        .font(.footnote)
        .foregroundColor(.gray.opacity(0.8))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
    }

    private var startButton: some View {
        Button {
            game.newGame(as: side, vsEngine: vsEngine, difficulty: difficulty)
            dismiss()
        } label: {
            Text("START MATCH")
                .font(.system(size: 19, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.17))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(BoardTheme.neonGreen)
                        .shadow(color: BoardTheme.neonGreen.opacity(0.45), radius: 18)
                )
        }
        .accessibilityIdentifier("startGame")
        .buttonStyle(.plain)
        .scaleEffect(appeared ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.2), value: appeared)
    }
}

struct PromotionSheet: View {
    @ObservedObject var game: GameState
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 16) {
            Text("Promote to")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .padding(.top, 20)
            HStack(spacing: 18) {
                ForEach([PieceType.queen, .rook, .bishop, .knight], id: \.rawValue) { t in
                    Button {
                        game.confirmPromotion(t)
                        dismiss()
                    } label: {
                        PieceArt(piece: BoardPiece(color: game.board.turn, type: t))
                            .frame(width: 64, height: 64)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.08)))
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .presentationDetents([.height(190)])
    }
}

// MARK: - Checkmate modal

struct MateModal: View {
    @ObservedObject var game: GameState
    let onShowOff: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text("localchess")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundColor(BoardTheme.neonGreen)
                    YetiPortrait(asset: (game.mateWon ?? false) ? "yeti-defeated" : "yeti-excited",
                                 label: (game.mateWon ?? false) ? "defeated yeti" : "celebrating yeti")
                        .frame(width: 56, height: 56)
                    MiniBoard(snapshot: game.board.snapshot())
                        .frame(width: 288, height: 288)
                    // Winner avatar: red buddy when the human wins.
                    Circle()
                        .fill(Color(red: 1.0, green: 0.28, blue: 0.28))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text("ʘʘ").foregroundColor(.white).font(.system(size: 16))
                        )
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(BoardTheme.background)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(BoardTheme.neonGreen)
                            .font(.system(size: 24))
                        Text(mateTitle)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundColor(BoardTheme.neonGreen)
                    }
                    Button(action: onShowOff) {
                        Text("SHOW IT OFF")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 0.10, green: 0.15, blue: 0.17))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .fill(BoardTheme.neonGreen))
                    }
                    Button(action: onContinue) {
                        Text("CONTINUE")
                            .accessibilityIdentifier("continueButton")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(BoardTheme.neonGreen)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: 14)
                                .stroke(BoardTheme.neonGreen.opacity(0.5), lineWidth: 2))
                    }
                }
                .padding(16)
                .background(Color(red: 0.07, green: 0.11, blue: 0.13))
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 40)
        }
    }

    private var mateTitle: String {
        switch game.status {
        case .checkmate(let winner):
            let you = !game.vsEngine ? true : (winner == game.playerColor)
            return you ? "Checkmate!" : "Checkmated!"
        case .stalemate: return "Stalemate!"
        case .draw: return "Draw!"
        case .timeout(let winner):
            let you = !game.vsEngine ? true : (winner == game.playerColor)
            return you ? "Time — you win!" : "Out of time!"
        case .ongoing: return ""
        }
    }
}

// MARK: - Confetti

struct ConfettiView: View {
    @State private var pieces: [ConfettiPiece] = (0..<70).map { _ in ConfettiPiece.random() }
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.color)
                        .frame(width: p.size, height: p.size * 0.6)
                        .position(x: p.x * geo.size.width, y: p.y * geo.size.height)
                        .rotationEffect(.degrees(p.rotation))
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 2.4)) {
                    for i in pieces.indices {
                        pieces[i].y = 1.15
                        pieces[i].rotation += 540
                    }
                }
            }
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var rotation: Double
    var size: CGFloat
    var color: Color
    var fallTime: Double

    static func random() -> ConfettiPiece {
        let colors: [Color] = [.green, .yellow, .pink, .blue, .orange, .white,
                               BoardTheme.neonGreen]
        return ConfettiPiece(
            x: Double.random(in: 0...1),
            y: Double.random(in: -0.25...0),
            rotation: Double.random(in: 0...360),
            size: CGFloat.random(in: 6...12),
            color: colors.randomElement() ?? .green,
            fallTime: Double.random(in: 1.8...2.6)
        )
    }
}

// MARK: - Share

extension UIImage: Identifiable {
    public var id: String { "\(hashValue)" }
}

struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
