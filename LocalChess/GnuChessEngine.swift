// GnuChessEngine.swift — LocalChess
// Local search engine in the spirit of GNU Chess (alpha-beta + piece-square
// evaluation, fully offline), plus a `GnuChessAdapter` that can drive a real
// `gnuchess --xboard` binary when installed (e.g. via Homebrew on macOS) and
// otherwise falls back to the built-in search. On iOS the built-in search is
// always used, so the game never needs network access.

import Foundation

enum EngineDifficulty: Int, CaseIterable, Identifiable {
    case chill = 0, clever, beast
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .chill: return "Chill"
        case .clever: return "Clever"
        case .beast: return "Beast"
        }
    }
    /// Search depth per level. Depth 3 + quiescence is plenty on a phone.
    var depth: Int {
        switch self {
        case .chill: return 1
        case .clever: return 2
        case .beast: return 3
        }
    }
    /// Think time handed to real GNU Chess via `go movetime` (milliseconds).
    var movetimeMs: Int {
        switch self {
        case .chill: return 250
        case .clever: return 800
        case .beast: return 2500
        }
    }
    /// Randomness (centipawns) to keep easy levels human.
    var jitter: Int {
        switch self {
        case .chill: return 60
        case .clever: return 18
        case .beast: return 0
        }
    }
}

// MARK: - Piece-square tables (white perspective, rank 0 = rank 1)

private enum PST {
    static let pawn: [Int] = [
         0,  0,  0,  0,  0,  0,  0,  0,
        50, 50, 50, 50, 50, 50, 50, 50,
        10, 10, 20, 30, 30, 20, 10, 10,
         5,  5, 10, 25, 25, 10,  5,  5,
         0,  0,  0, 20, 20,  0,  0,  0,
         5, -5,-10,  0,  0,-10, -5,  5,
         5, 10, 10,-20,-20, 10, 10,  5,
         0,  0,  0,  0,  0,  0,  0,  0
    ]
    static let knight: [Int] = [
        -50,-40,-30,-30,-30,-30,-40,-50,
        -40,-20,  0,  0,  0,  0,-20,-40,
        -30,  0, 10, 15, 15, 10,  0,-30,
        -30,  5, 15, 20, 20, 15,  5,-30,
        -30,  0, 15, 20, 20, 15,  0,-30,
        -30,  5, 10, 15, 15, 10,  5,-30,
        -40,-20,  0,  5,  5,  0,-20,-40,
        -50,-40,-30,-30,-30,-30,-40,-50
    ]
    static let bishop: [Int] = [
        -20,-10,-10,-10,-10,-10,-10,-20,
        -10,  0,  0,  0,  0,  0,  0,-10,
        -10,  0,  5, 10, 10,  5,  0,-10,
        -10,  5,  5, 10, 10,  5,  5,-10,
        -10,  0, 10, 10, 10, 10,  0,-10,
        -10, 10, 10, 10, 10, 10, 10,-10,
        -10,  5,  0,  0,  0,  0,  5,-10,
        -20,-10,-10,-10,-10,-10,-10,-20
    ]
    static let rook: [Int] = [
          0,  0,  0,  0,  0,  0,  0,  0,
          5, 10, 10, 10, 10, 10, 10,  5,
         -5,  0,  0,  0,  0,  0,  0, -5,
         -5,  0,  0,  0,  0,  0,  0, -5,
         -5,  0,  0,  0,  0,  0,  0, -5,
         -5,  0,  0,  0,  0,  0,  0, -5,
         -5,  0,  0,  0,  0,  0,  0, -5,
          0,  0,  0,  5,  5,  0,  0,  0
    ]
    static let queen: [Int] = [
        -20,-10,-10, -5, -5,-10,-10,-20,
        -10,  0,  0,  0,  0,  0,  0,-10,
        -10,  0,  5,  5,  5,  5,  0,-10,
         -5,  0,  5,  5,  5,  5,  0, -5,
          0,  0,  5,  5,  5,  5,  0, -5,
        -10,  5,  5,  5,  5,  5,  0,-10,
        -10,  0,  5,  0,  0,  0,  0,-10,
        -20,-10,-10, -5, -5,-10,-10,-20
    ]
    static let king: [Int] = [
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -30,-40,-40,-50,-50,-40,-40,-30,
        -20,-30,-30,-40,-40,-30,-30,-20,
        -10,-20,-20,-20,-20,-20,-20,-10,
         20, 20,  0,  0,  0,  0, 20, 20,
         20, 30, 10,  0,  0, 10, 30, 20
    ]

    static func value(type: PieceType, square: Int, color: PieceColor) -> Int {
        // Tables are written white-perspective; mirror for black.
        let idx: Int
        if color == .white { idx = square }
        else { idx = (7 - Square.rank(of: square)) * 8 + Square.file(of: square) }
        switch type {
        case .pawn: return pawn[idx]
        case .knight: return knight[idx]
        case .bishop: return bishop[idx]
        case .rook: return rook[idx]
        case .queen: return queen[idx]
        case .king: return king[idx]
        }
    }
}

// MARK: - Built-in search

/// Negamax alpha-beta search with MVV-LVA ordering and a captures-only
/// quiescence layer. Synchronous; callers run it off the main thread.
struct LocalSearchEngine {
    var nodes = 0
    var nodeLimit = 120_000
    let mateScore = 100_000

    static func evaluate(_ board: ChessBoard) -> Int {
        var score = 0
        for sq in 0..<64 {
            guard let p = board.squares[sq] else { continue }
            let v = p.type.value + PST.value(type: p.type, square: sq, color: p.color)
            score += (p.color == .white) ? v : -v
        }
        return board.turn == .white ? score : -score
    }

    static func orderScore(_ move: ChessMove) -> Int {
        var s = 0
        if let victim = move.captured { s += 10 * victim.value }
        if let promo = move.promotion { s += promo.value }
        if let attackerSqValue = move.captured.map({ _ in 0 }) { s += attackerSqValue }
        return s
    }

    mutating func quiescence(_ board: inout ChessBoard, alpha: Int, beta: Int, depth: Int) -> Int {
        nodes += 1
        if nodes > nodeLimit { return LocalSearchEngine.evaluate(board) }
        let stand = LocalSearchEngine.evaluate(board)
        if depth <= 0 { return stand }
        if stand >= beta { return beta }
        var a = max(alpha, stand)
        let captures = board.legalMoves(for: board.turn)
            .filter { $0.isCapture }
            .sorted { LocalSearchEngine.orderScore($0) > LocalSearchEngine.orderScore($1) }
        for m in captures.prefix(12) {
            var child = board
            child.apply(m)
            let score = -quiescence(&child, alpha: -beta, beta: -a, depth: depth - 1)
            if score >= beta { return beta }
            a = max(a, score)
        }
        return a
    }

    mutating func negamax(_ board: inout ChessBoard, depth: Int, alpha: Int, beta: Int, ply: Int) -> Int {
        nodes += 1
        if nodes > nodeLimit { return LocalSearchEngine.evaluate(board) }
        if board.halfmoveClock >= 100 || board.insufficientMaterial() { return 0 }
        let moves = board.legalMoves(for: board.turn)
        if moves.isEmpty {
            if board.isInCheck(board.turn) { return -mateScore + ply }
            return 0
        }
        if depth <= 0 {
            return quiescence(&board, alpha: alpha, beta: beta, depth: 4)
        }
        var a = alpha
        let ordered = moves.sorted { LocalSearchEngine.orderScore($0) > LocalSearchEngine.orderScore($1) }
        for m in ordered {
            var child = board
            child.apply(m)
            let score = -negamax(&child, depth: depth - 1, alpha: -beta, beta: -a, ply: ply + 1)
            if score >= beta { return beta }
            a = max(a, score)
        }
        return a
    }

    /// Returns the best move for the side to move, or nil if none.
    mutating func bestMove(in board: ChessBoard, depth: Int, jitter: Int) -> ChessMove? {
        let moves = board.legalMoves(for: board.turn)
        guard !moves.isEmpty else { return nil }
        if moves.count == 1 { return moves[0] }
        var scored: [(ChessMove, Int)] = []
        let ordered = moves.sorted { LocalSearchEngine.orderScore($0) > LocalSearchEngine.orderScore($1) }
        for m in ordered {
            var child = board
            child.apply(m)
            let score = -negamax(&child, depth: depth - 1, alpha: -1_000_000, beta: 1_000_000, ply: 1)
            let wobble = jitter > 0 ? Int.random(in: -jitter...jitter) : 0
            scored.append((m, score + wobble))
            if nodes > nodeLimit { break }
        }
        return scored.max(by: { $0.1 < $1.1 })?.0
    }
}

// MARK: - GNU Chess adapter

/// Drives the real GNU Chess engine (6.2.5, vendored C++ under
/// LocalChess/gnuchess, GPLv3 — see gnuchess/COPYING). The engine runs on
/// its own pthread and speaks UCI over two POSIX pipes via GnuChessBridge;
/// no frontend/adapter processes, no stdin/stdout tricks, no network.
/// Every reply is validated against our own legal move generator before it
/// is played, and any failure transparently falls back to the built-in
/// `LocalSearchEngine`, so the game can never get stuck without a move.
final class GnuChessAdapter {
    static let shared = GnuChessAdapter()

    private let bridge = GnuChessBridge()

    /// What powers the coach. Shown in the menu for transparency.
    var engineName: String { "GNU Chess 6.2.5" }

    var engineStatusText: String {
        "GNU Chess 6.2.5 engine, linked into the app. 100% offline — no network needed."
    }

    /// Async best-move lookup. `uciMoves` is the full game in UCI coordinate
    /// notation from the start position, so GNU Chess reconstructs the exact
    /// position (castling rights, en passant) by replay.
    func bestMove(in board: ChessBoard, difficulty: EngineDifficulty, uciMoves: [String]) async -> ChessMove? {
        if let reply = await gnuReply(uciMoves: uciMoves, movetimeMs: difficulty.movetimeMs),
           let match = match(reply: reply, in: board) {
            return match
        }
        // Fallback: built-in search (same contract, fully offline).
        NSLog("[LocalChess] GNU Chess unavailable; using built-in fallback")
        return await Task.detached(priority: .userInitiated) {
            var engine = LocalSearchEngine()
            return engine.bestMove(in: board, depth: difficulty.depth, jitter: difficulty.jitter)
        }.value
    }

    /// Clears the engine's transposition table. Call on new game.
    func newGame() {
        let bridge = bridge
        Task.detached(priority: .utility) {
            if bridge.started() { bridge.sendNewGame() }
        }
    }

    // MARK: UCI over the bridge (always off the main thread)

    private func gnuReply(uciMoves: [String], movetimeMs: Int) async -> String? {
        await Task.detached(priority: .userInitiated) { [bridge] in
            guard bridge.start() else { return nil }
            guard let reply = bridge.bestMove(withMoves: uciMoves,
                                              movetimeMs: movetimeMs) else { return nil }
            NSLog("[LocalChess] GNU Chess says %@", reply)
            return reply
        }.value
    }

    /// Parses "e2e4" / "e7e8q" and matches it against our legal moves, so a
    /// surprising reply can never produce an illegal position.
    private func match(reply: String, in board: ChessBoard) -> ChessMove? {
        let files = Array("abcdefgh")
        let chars = Array(reply.lowercased())
        guard chars.count >= 4,
              let ff = files.firstIndex(of: chars[0]),
              let tf = files.firstIndex(of: chars[2]),
              let fr = chars[1].wholeNumberValue, (1...8).contains(fr),
              let tr = chars[3].wholeNumberValue, (1...8).contains(tr) else {
            return nil
        }
        let from = Square.make(file: ff, rank: fr - 1)
        let to = Square.make(file: tf, rank: tr - 1)
        var promotion: PieceType?
        if chars.count >= 5 {
            switch chars[4] {
            case "q": promotion = .queen
            case "r": promotion = .rook
            case "b": promotion = .bishop
            case "n": promotion = .knight
            default: return nil
            }
        }
        return board.legalMoves(for: board.turn).first {
            $0.from == from && $0.to == to && $0.promotion == promotion
        }
    }
}
