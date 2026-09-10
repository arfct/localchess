// GameState.swift — LocalChess
// Observable game controller: position, history (undo/redo), timer, points,
// coach commentary, engine turns, and end-of-game state.

import Foundation
import SwiftUI
import Combine

enum PlayerSide { case white, black }

@MainActor
final class GameState: ObservableObject {
    @Published var board = ChessBoard()
    @Published var selected: Int? = nil
    @Published var legalTargets: [ChessMove] = []
    @Published var status: GameResult = .ongoing
    @Published var playerSide: PlayerSide = .white
    @Published var difficulty: EngineDifficulty = .clever
    @Published var engineThinking = false
    @Published var secondsLeft = 15 * 60
    @Published var points = 0
    @Published var coachMessage = "Fresh snow! Come test the Yeti."
    @Published var coachMood: CoachMood = .thinking
    @Published var showMateModal = false
    @Published var mateWon: Bool? = nil
    @Published var pendingPromotion: ChessMove? = nil
    @Published var lastCaptureWasQueen = false
    @Published var moveCount = 0
    // Post-game review (engine-graded moves + replay).
    @Published var review: GameReview? = nil
    @Published var reviewing = false
    @Published var reviewProgress = 0.0

    /// When false, both sides are human (local 2-player).
    @Published var vsEngine = true

    private var history: [PositionSnapshot] = []
    private var redoStack: [PositionSnapshot] = []
    /// Running points totals parallel to the position stacks, so undo/redo
    /// restores the exact cumulative total instead of recomputing it.
    private var historyPoints: [Int] = []
    private var redoPoints: [Int] = []
    /// Full game in UCI coordinate notation for the GNU Chess engine, plus
    /// the redo counterpart. Mirrors history/redoStack exactly.
    private var uciMoves: [String] = []
    private var redoUci: [String] = []
    private var timer: AnyCancellable?
    private var engineTask: Task<Void, Never>?
    private var reviewTask: Task<Void, Never>?

    var playerColor: PieceColor { playerSide == .white ? .white : .black }
    var isGameOver: Bool {
        switch status {
        case .ongoing: return false
        default: return true
        }
    }

    /// Board orientation: white at bottom unless the player is black.
    var flipped: Bool { vsEngine ? (playerSide == .black) : false }

    init() { startTimer() }

    // MARK: - Game setup

    func newGame(as side: PlayerSide, vsEngine: Bool = true, difficulty: EngineDifficulty? = nil) {
        engineTask?.cancel()
        clearReview()
        board = ChessBoard()
        history = []
        redoStack = []
        historyPoints = []
        redoPoints = []
        uciMoves = []
        redoUci = []
        ArasanAdapter.shared.newGame()
        selected = nil
        legalTargets = []
        status = .ongoing
        playerSide = side
        self.vsEngine = vsEngine
        if let d = difficulty { self.difficulty = d }
        engineThinking = false
        secondsLeft = 15 * 60
        points = 0
        moveCount = 0
        showMateModal = false
        mateWon = nil
        pendingPromotion = nil
        coachMessage = CoachLines.opening.randomElement() ?? "Fresh snow! Come test the Yeti."
        coachMood = .thinking
        HapticManager.shared.gameStart()
        maybeEngineMove()
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.tick() }
            }
    }

    private func tick() {
        guard !isGameOver else { return }
        if secondsLeft > 0 {
            secondsLeft -= 1
            if secondsLeft == 0 {
                // Flag fall: the side to move loses on time.
                let winner = board.turn.opposite
                status = .timeout(winner: winner)
                onGameEnd(status)
            }
        }
    }

    var clockText: String {
        String(format: "%02d:%02d", secondsLeft / 60, secondsLeft % 60)
    }

    // MARK: - Selection & moves

    /// Square tapped in display coordinates (already orientation-adjusted by caller).
    func tap(square: Int) {
        guard !isGameOver, !engineThinking else { return }
        if vsEngine && board.turn != playerColor { return }

        // If a piece is selected and this is one of its targets, move there.
        if let sel = selected,
           let mv = legalTargets.first(where: { $0.from == sel && $0.to == square }) {
            if mv.promotion != nil {
                // Human promotion: ask which piece (default queen in the sheet).
                pendingPromotion = mv
                return
            }
            doMove(mv)
            return
        }

        // Otherwise (re)select own piece.
        if let p = board.squares[square], p.color == board.turn {
            if vsEngine && p.color != playerColor { return }
            selected = square
            legalTargets = board.legalMoves(for: board.turn).filter { $0.from == square }
            HapticManager.shared.select()
        } else {
            if selected != nil { HapticManager.shared.illegal() }
            selected = nil
            legalTargets = []
        }
    }

    func confirmPromotion(_ type: PieceType) {
        guard var mv = pendingPromotion else { return }
        mv.promotion = type
        pendingPromotion = nil
        doMove(mv)
    }

    func doMove(_ move: ChessMove) {
        var move = move
        // Safety: recompute capture info from the real board.
        if !move.isEnPassant, let victim = board.squares[move.to] {
            move.captured = victim.type
        }
        history.append(board.snapshot())
        redoStack = []
        historyPoints.append(points)
        redoPoints = []
        uciMoves.append(move.uci)
        redoUci = []

        let mover = board.turn
        let wasCapture = move.isCapture
        let capturedType = move.captured ?? (move.isEnPassant ? .pawn : nil)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            board.apply(move)
        }
        selected = nil
        legalTargets = []
        moveCount += 1
        lastCaptureWasQueen = (capturedType == .queen)

        // Haptics: moves tick, captures blast, queen captures go crazy.
        if wasCapture { HapticManager.shared.capture(captured: capturedType) }
        else { HapticManager.shared.move() }

        // Cumulative running total, credited toward the taker's side: in
        // 2-player mode the pill tracks White's net (Black scores negative).
        // Coach lines still follow who took whom.
        let humanMoved = !vsEngine || mover == playerColor
        let plusSide: PieceColor = vsEngine ? playerColor : .white
        if let cap = capturedType {
            points += (mover == plusSide ? cap.points : -cap.points)
            if humanMoved {
                coachMessage = CoachLines.playerCapture.randomElement() ?? coachMessage
                coachMood = .happy
            }
        }

        let result = board.result()
        if board.isInCheck(board.turn) && (result == .ongoing) {
            HapticManager.shared.check()
            if mover == plusSide { points += 2 }
            if humanMoved {
                // Human gave check: the yeti is rattled.
                coachMessage = CoachLines.playerCheck.randomElement() ?? coachMessage
                coachMood = .worried
            } else {
                // Yeti gave check: it gloats.
                coachMessage = CoachLines.engineCheck.randomElement() ?? coachMessage
                coachMood = .happy
            }
        } else if !humanMoved && wasCapture {
            coachMessage = CoachLines.engineCapture.randomElement() ?? coachMessage
            coachMood = .happy
        }

        if case .ongoing = result {
            status = result
            maybeEngineMove()
        } else {
            status = result
            onGameEnd(result)
        }
    }

    // MARK: - Engine

    private func maybeEngineMove() {
        guard vsEngine, !isGameOver else { return }
        guard board.turn != playerColor else { return }
        engineThinking = true
        engineTask?.cancel()
        let position = board
        let level = difficulty
        engineTask = Task { [weak self] in
            // Small beat so the player's move lands visually first.
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let gameMoves = await MainActor.run { self.uciMoves }
            guard !Task.isCancelled else { return }
            let reply = await ArasanAdapter.shared.bestMove(in: position, difficulty: level, uciMoves: gameMoves)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.engineThinking = false
                guard let reply else { return }
                // Promotion choice for engine: always queen.
                self.doMove(reply)
            }
        }
    }

    // MARK: - Post-game review

    /// Drop any review state (positions changed or new game).
    func clearReview() {
        reviewTask?.cancel()
        reviewTask = nil
        reviewing = false
        reviewProgress = 0
        review = nil
    }

    func cancelReview() {
        reviewTask?.cancel()
        reviewTask = nil
        reviewing = false
    }

    /// Grade every move with the engine (background, ~0.4s per position).
    /// Cached: reopening a finished review does not re-analyze.
    func startReview() {
        if review != nil || reviewing { return }
        guard isGameOver else { return }
        reviewing = true
        reviewProgress = 0
        review = nil
        let moves = uciMoves
        let final = status
        let human: PieceColor? = vsEngine ? playerColor : nil
        reviewTask?.cancel()
        NSLog("[LocalChess] review started (%d moves)", moves.count)
        reviewTask = Task { [weak self] in
            let evals = await ArasanAdapter.shared.reviewEvals(
                moves: moves, movetimeMs: 400
            ) { [weak self] p in
                Task { @MainActor in self?.reviewProgress = p }
            }
            NSLog("[LocalChess] review evals done (%d)", evals.count)
            guard !Task.isCancelled else { return }
            let built = GameReview.build(moves: moves, evals: evals,
                                         final: final, human: human)
            NSLog("[LocalChess] review built (%d graded)", built.moves.count)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.review = built
                self.reviewing = false
                HapticManager.shared.checkmate(playerWon: true)
            }
        }
    }

    // MARK: - Undo / redo

    var canUndo: Bool { !history.isEmpty && !engineThinking }
    var canRedo: Bool { !redoStack.isEmpty && !engineThinking }

    func undo() {
        guard canUndo else { return }
        engineTask?.cancel()
        clearReview()
        engineThinking = false
        // Against the engine, revert a full round (engine + player) when possible.
        let steps = (vsEngine && history.count >= 2 && board.turn == playerColor) ? 2 : 1
        for _ in 0..<steps {
            guard let prev = history.popLast(), let pp = historyPoints.popLast() else { break }
            redoStack.append(board.snapshot())
            redoPoints.append(points)
            if !uciMoves.isEmpty { redoUci.append(uciMoves.removeLast()) }
            board.restore(prev)
            points = pp
            moveCount = max(0, moveCount - 1)
        }
        selected = nil
        legalTargets = []
        status = .ongoing
        showMateModal = false
        mateWon = nil
        HapticManager.shared.select()
    }

    func redo() {
        guard canRedo else { return }
        clearReview()
        let steps = (vsEngine && redoStack.count >= 2) ? 2 : 1
        for _ in 0..<steps {
            guard let next = redoStack.popLast(), let rp = redoPoints.popLast() else { break }
            history.append(board.snapshot())
            historyPoints.append(points)
            if !redoUci.isEmpty { uciMoves.append(redoUci.removeLast()) }
            board.restore(next)
            points = rp
            moveCount += 1
        }
        selected = nil
        legalTargets = []
        status = board.result()
        HapticManager.shared.select()
        if case .ongoing = status { maybeEngineMove() }
        else { presentGameEnd(status) }
    }

    // MARK: - Game end

    /// Fresh end of game: awards, haptics, then presentation.
    private func onGameEnd(_ result: GameResult) {
        let plusSide: PieceColor = vsEngine ? playerColor : .white
        switch result {
        case .checkmate(let winner):
            let won = !vsEngine ? true : (winner == playerColor)
            HapticManager.shared.checkmate(playerWon: won)
            points += (winner == plusSide ? 25 : -25)
            // Bubble portrait follows the result: sad yeti on your win,
            // crowned yeti on its win (matches the mate card).
        case .stalemate:
            HapticManager.shared.check()
        case .draw:
            break
        case .timeout(let winner):
            let won = !vsEngine ? true : (winner == playerColor)
            HapticManager.shared.checkmate(playerWon: won)
        case .ongoing:
            break
        }
        presentGameEnd(result)
    }

    /// End-of-game presentation only: no points, no haptics. Used when
    /// redoing into an already-decided position so totals are never
    /// awarded twice.
    private func presentGameEnd(_ result: GameResult) {
        selected = nil
        legalTargets = []
        engineThinking = false
        switch result {
        case .checkmate(let winner):
            let won = !vsEngine ? true : (winner == playerColor)
            mateWon = won
            coachMessage = won ? (CoachLines.mateWin.randomElement() ?? "Checkmate!") :
                                 (CoachLines.mateLose.randomElement() ?? "Checkmate.")
            coachMood = won ? .sad : .excited
            showMateModal = true
        case .stalemate:
            mateWon = nil
            coachMessage = "Stalemate — we both freeze."
            coachMood = .thinking
            showMateModal = true
        case .draw(let reason):
            mateWon = nil
            coachMessage = "Draw: \(reason)."
            coachMood = .thinking
            showMateModal = true
        case .timeout(let winner):
            let won = !vsEngine ? true : (winner == playerColor)
            mateWon = won
            coachMessage = won ? "Flag! You outran the blizzard." : "Flag — frozen out. Yeti wins."
            coachMood = won ? .sad : .excited
            showMateModal = true
        case .ongoing:
            break
        }
    }
}

// MARK: - Coach content (original lines in the reference's spirit)

enum CoachMood { case thinking, happy, excited, worried, sad }

enum CoachLines {
    static let opening = [
        "Fresh snow! Come test the Yeti.",
        "You bring the moves, I bring the blizzard.",
        "No avalanche fear. Just chess.",
        "I sharpened my claws for this."
    ]
    static let playerCapture = [
        "RAWR! That one was mine.",
        "Bold, little climber.",
        "My piece! The cave mourns.",
        "Ouch. My fur stands up."
    ]
    static let engineCapture = [
        "Mine now. The cave provides.",
        "Snatched straight from the snow.",
        "Yeti smash... politely.",
        "Into my collection, warm and safe."
    ]
    static let playerCheck = [
        "Brrr! Checked me.",
        "Hey — my den is under attack!",
        "Rude. Effective, but rude."
    ]
    static let engineCheck = [
        "Check. Cold, right?",
        "Your king shivers already.",
        "Say hi to my claws."
    ]
    static let mateWin = [
        "Checkmate! The mountain bows to you.",
        "You got me. Snow happens.",
        "Beautiful finish. Rematch in my cave?"
    ]
    static let mateLose = [
        "Checkmate. The peak is MINE.",
        "RAWR! Yeti reigns supreme.",
        "Better luck next blizzard, climber."
    ]
}
