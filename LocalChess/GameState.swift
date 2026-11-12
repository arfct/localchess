// GameState.swift — LocalChess
// Observable game controller: position, history (undo/redo), timer, points,
// coach commentary, engine turns, and end-of-game state.

import Foundation
import SwiftUI
import Combine

enum PlayerSide { case white, black }

/// How long each side has for the whole game. The clock of the side to move
/// runs; against the yeti only yours does (it thinks on its own time).
enum TimeControl: Int, CaseIterable, Identifiable {
    case untimed = 0, five = 5, ten = 10, fifteen = 15
    var id: Int { rawValue }
    var seconds: Int { rawValue * 60 }
    var title: String { self == .untimed ? "No clock" : "\(rawValue) min" }
}

@MainActor
final class GameState: ObservableObject {
    @Published var board = ChessBoard()
    @Published var selected: Int? = nil
    @Published var legalTargets: [ChessMove] = []
    @Published var status: GameResult = .ongoing
    @Published var playerSide: PlayerSide = .white
    @Published var difficulty: EngineDifficulty = .clever
    @Published var engineThinking = false
    @Published var timeControl: TimeControl = .fifteen
    @Published var whiteSeconds = 15 * 60
    @Published var blackSeconds = 15 * 60
    /// The game so far in SAN ("e4", "Nf3", "O-O"), one entry per ply.
    @Published var sanMoves: [String] = []
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
    private var redoSan: [String] = []
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

    init() {
        restore()
        startTimer()
        maybeEngineMove()
    }

    // MARK: - Saving

    /// Everything needed to pick a game up where it was left.
    private struct Saved: Codable {
        var board: ChessBoard
        var history: [PositionSnapshot], redoStack: [PositionSnapshot]
        var historyPoints: [Int], redoPoints: [Int]
        var uciMoves: [String], redoUci: [String]
        var sanMoves: [String], redoSan: [String]
        var playerWhite: Bool, vsEngine: Bool, difficulty: Int, timeControl: Int
        var whiteSeconds: Int, blackSeconds: Int, points: Int, moveCount: Int
    }

    private static var saveURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("game.json")
    }

    /// Writes the game out. Called after every change to it.
    func save() {
        let g = Saved(board: board, history: history, redoStack: redoStack,
                      historyPoints: historyPoints, redoPoints: redoPoints,
                      uciMoves: uciMoves, redoUci: redoUci, sanMoves: sanMoves, redoSan: redoSan,
                      playerWhite: playerSide == .white, vsEngine: vsEngine,
                      difficulty: difficulty.rawValue, timeControl: timeControl.rawValue,
                      whiteSeconds: whiteSeconds, blackSeconds: blackSeconds,
                      points: points, moveCount: moveCount)
        do {
            try FileManager.default.createDirectory(at: Self.saveURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(g).write(to: Self.saveURL, options: .atomic)
        } catch {
            NSLog("[LocalChess] save failed: %@", "\(error)")
        }
    }

    private func restore() {
        // UI tests start from a fresh board.
        if ProcessInfo.processInfo.arguments.contains("-LCFresh") { return }
        guard let data = try? Data(contentsOf: Self.saveURL),
              let g = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        board = g.board
        history = g.history; redoStack = g.redoStack
        historyPoints = g.historyPoints; redoPoints = g.redoPoints
        uciMoves = g.uciMoves; redoUci = g.redoUci
        sanMoves = g.sanMoves; redoSan = g.redoSan
        playerSide = g.playerWhite ? .white : .black
        vsEngine = g.vsEngine
        difficulty = EngineDifficulty(rawValue: g.difficulty) ?? .clever
        timeControl = TimeControl(rawValue: g.timeControl) ?? .fifteen
        whiteSeconds = g.whiteSeconds; blackSeconds = g.blackSeconds
        points = g.points; moveCount = g.moveCount
        status = board.result()
        if whiteSeconds == 0 && hasClock(.white) { status = .timeout(winner: .black) }
        if blackSeconds == 0 && hasClock(.black) { status = .timeout(winner: .white) }
        if isGameOver { presentGameEnd(status); showMateModal = false }
    }

    // MARK: - Game setup

    func newGame(as side: PlayerSide, vsEngine: Bool = true, difficulty: EngineDifficulty? = nil,
                 timeControl: TimeControl? = nil) {
        engineTask?.cancel()
        clearReview()
        board = ChessBoard()
        history = []
        redoStack = []
        historyPoints = []
        redoPoints = []
        uciMoves = []
        redoUci = []
        sanMoves = []
        redoSan = []
        ArasanAdapter.shared.newGame()
        selected = nil
        legalTargets = []
        status = .ongoing
        playerSide = side
        self.vsEngine = vsEngine
        if let d = difficulty { self.difficulty = d }
        engineThinking = false
        if let t = timeControl { self.timeControl = t }
        whiteSeconds = self.timeControl.seconds
        blackSeconds = self.timeControl.seconds
        points = 0
        moveCount = 0
        showMateModal = false
        mateWon = nil
        pendingPromotion = nil
        coachMessage = CoachLines.opening.randomElement() ?? "Fresh snow! Come test the Yeti."
        coachMood = .thinking
        HapticManager.shared.gameStart()
        save()
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

    /// Whether this side plays against a clock at all.
    func hasClock(_ color: PieceColor) -> Bool {
        timeControl != .untimed && (!vsEngine || color == playerColor)
    }

    /// The clock that's running now, if any. Clocks start with the first
    /// move, so nobody loses time reading the menu.
    var runningClock: PieceColor? {
        guard !isGameOver, moveCount > 0, hasClock(board.turn) else { return nil }
        return board.turn
    }

    func seconds(_ color: PieceColor) -> Int {
        color == .white ? whiteSeconds : blackSeconds
    }

    func clockText(_ color: PieceColor) -> String {
        let s = seconds(color)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func tick() {
        guard let side = runningClock, seconds(side) > 0 else { return }
        if side == .white { whiteSeconds -= 1 } else { blackSeconds -= 1 }
        if seconds(side) % 5 == 0 { save() }
        if seconds(side) == 0 {
            // Flag fall: the side to move loses on time.
            status = .timeout(winner: side.opposite)
            onGameEnd(status)
        }
    }

    /// Pieces each side has taken, worst first, and the material lead
    /// (in pawns) of `color` over the other side.
    func captured(by color: PieceColor) -> [PieceType] {
        let start: [PieceType: Int] = [.pawn: 8, .knight: 2, .bishop: 2, .rook: 2, .queen: 1]
        var left: [PieceType: Int] = [:]
        for p in board.squares.compactMap({ $0 }) where p.color == color.opposite {
            left[p.type, default: 0] += 1
        }
        var out: [PieceType] = []
        for t in [PieceType.pawn, .knight, .bishop, .rook, .queen] {
            out += Array(repeating: t, count: max(0, start[t]! - left[t, default: 0]))
        }
        return out
    }

    func materialLead(_ color: PieceColor) -> Int {
        var n = 0
        for p in board.squares.compactMap({ $0 }) where p.type != .king {
            n += (p.color == color ? 1 : -1) * p.type.points
        }
        return n
    }

    // MARK: - Selection & moves

    /// Whether a person may touch the board now.
    var canInteract: Bool {
        !isGameOver && !engineThinking && pendingPromotion == nil
            && (!vsEngine || board.turn == playerColor)
    }

    /// Whether the piece on `square` can be picked up.
    func canPickUp(_ square: Int) -> Bool {
        canInteract && board.squares[square]?.color == board.turn
    }

    func select(_ square: Int) {
        guard canPickUp(square) else { return }
        if selected == square { return }
        selected = square
        legalTargets = board.legalMoves(for: board.turn).filter { $0.from == square }
        HapticManager.shared.select()
    }

    func deselect() {
        selected = nil
        legalTargets = []
    }

    /// Plays from → to if it's legal (asking for the piece on a promotion).
    /// Returns false, leaving everything as it was, if it isn't.
    @discardableResult
    func move(from: Int, to: Int) -> Bool {
        guard canInteract,
              let mv = board.legalMoves(for: board.turn).first(where: { $0.from == from && $0.to == to })
        else { return false }
        if mv.promotion != nil {
            selected = from
            pendingPromotion = mv
            return true
        }
        doMove(mv)
        return true
    }

    /// A tap on a square: move the selected piece there, pick up the piece
    /// there, or put the selection down.
    func tap(square: Int) {
        guard canInteract else { return }
        if let sel = selected, sel != square, move(from: sel, to: square) { return }
        if selected == square {
            deselect()
        } else if canPickUp(square) {
            select(square)
        } else {
            if selected != nil { HapticManager.shared.illegal() }
            deselect()
        }
    }

    func confirmPromotion(_ type: PieceType) {
        guard var mv = pendingPromotion else { return }
        mv.promotion = type
        pendingPromotion = nil
        doMove(mv)
    }

    func cancelPromotion() {
        pendingPromotion = nil
        deselect()
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
        sanMoves.append(GameReview.sanString(for: move, on: board, legal: board.legalMoves(for: board.turn)))
        redoSan = []

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
        save()
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
        pendingPromotion = nil
        // Against the engine, revert a full round (engine + player) when possible.
        let steps = (vsEngine && history.count >= 2 && board.turn == playerColor) ? 2 : 1
        for _ in 0..<steps {
            guard let prev = history.popLast(), let pp = historyPoints.popLast() else { break }
            redoStack.append(board.snapshot())
            redoPoints.append(points)
            if !uciMoves.isEmpty { redoUci.append(uciMoves.removeLast()) }
            if !sanMoves.isEmpty { redoSan.append(sanMoves.removeLast()) }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { board.restore(prev) }
            points = pp
            moveCount = max(0, moveCount - 1)
        }
        selected = nil
        legalTargets = []
        status = .ongoing
        showMateModal = false
        mateWon = nil
        HapticManager.shared.select()
        save()
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
            if !redoSan.isEmpty { sanMoves.append(redoSan.removeLast()) }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { board.restore(next) }
            points = rp
            moveCount += 1
        }
        selected = nil
        legalTargets = []
        status = board.result()
        HapticManager.shared.select()
        if case .ongoing = status { maybeEngineMove() }
        else { presentGameEnd(status) }
        save()
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
