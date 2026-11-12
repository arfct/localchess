// GameReview.swift — LocalChess
// Post-game coaching: engine grades every move by centipawn loss, flags
// blunders/misses/dubious moves, and replays the game on a scrub board.

import Foundation

/// Coaching tier for one played move.
enum MoveTier: Equatable {
    case best      // matched the engine's top choice
    case good      // small/no loss
    case dubious   // ?! loss >= 60cp
    case miss      // ?  loss >= 120cp
    case blunder   // ?? loss >= 250cp
    case unknown   // engine had no verdict

    var glyph: String? {
        switch self {
        case .best: return nil
        case .good: return nil
        case .dubious: return "?!"
        case .miss: return "?"
        case .blunder: return "??"
        case .unknown: return nil
        }
    }

    var label: String? {
        switch self {
        case .best: return "Best"
        case .good: return nil
        case .dubious: return "Dubious"
        case .miss: return "Miss"
        case .blunder: return "Blunder"
        case .unknown: return nil
        }
    }

    static func quip(for tier: MoveTier) -> String {
        switch tier {
        case .blunder: return "Ouch. The whole mountain saw that one."
        case .miss: return "There was treasure there, climber."
        case .dubious: return "Hmm. A frosty choice."
        case .best: return "Now THAT is a yeti-approved move."
        case .good: return "Solid. Like packed snow."
        case .unknown: return "The snow hides this one from me."
        }
    }
}

/// One graded move plus everything the replay board needs.
struct ReviewedMove {
    /// Ply index (0-based). Even plies are White's.
    let ply: Int
    let uci: String
    let san: String
    let mover: PieceColor
    let bestUci: String?
    let bestSan: String?
    /// Centipawn loss from the mover's perspective (nil = unknown).
    let loss: Int?
    let tier: MoveTier
}

/// Whole-game verdict: graded moves, snapshots per position (0...n), and a
/// 0-100 yeti score over the reviewed side's average centipawn loss.
struct GameReview {
    let moves: [ReviewedMove]
    /// Board contents before each ply, plus the final position.
    let positions: [[BoardPiece?]]
    let accuracy: Int
    var blunders: Int { moves.filter { $0.tier == .blunder }.count }
    var misses: Int { moves.filter { $0.tier == .miss }.count }

    /// Build from engine verdicts (one per prefix position). Terminal final
    /// positions are scored by rule; `human` selects whose moves count
    /// toward the score (nil = both sides, for local 2-player).
    static func build(moves uciMoves: [String], evals: [EngineEval?],
                      final: GameResult, human: PieceColor?) -> GameReview {
        var board = ChessBoard()
        var positions: [[BoardPiece?]] = [board.squares]
        var out: [ReviewedMove] = []

        // Side-to-move score per position; terminal finals by rule.
        var scores: [Int?] = evals.map { $0?.scoreCp }
        var bests: [String?] = evals.map { $0?.bestUci }
        if scores.count == uciMoves.count + 1 {
            let sideToMove: PieceColor = (uciMoves.count % 2 == 0) ? .white : .black
            switch final {
            case .checkmate(let winner):
                // Side to move was mated: -100000 from their perspective.
                scores[uciMoves.count] = (sideToMove == winner) ? 0 : -100000
            case .stalemate, .draw:
                scores[uciMoves.count] = 0
            case .timeout, .ongoing:
                break
            }
        }

        for (i, uci) in uciMoves.enumerated() {
            let mover: PieceColor = (i % 2 == 0) ? .white : .black
            let legal = board.legalMoves(for: mover)
            guard let mv = matchUci(uci, on: board) else {
                positions.append(board.squares)
                continue
            }
            let san = sanString(for: mv, on: board, legal: legal)
            var bestSan: String? = nil
            if let b = bests[i], let bm = matchUci(b, on: board) {
                bestSan = sanString(for: bm, on: board, legal: legal)
            }
            var loss: Int? = nil
            if i + 1 < scores.count, let s0 = scores[i], let s1 = scores[i + 1] {
                // Both side-to-move: loss = before + after-from-opponent-view.
                loss = max(0, s0 + s1)
            }
            let tier: MoveTier
            if uci == bests[i] {
                tier = .best
            } else if let l = loss {
                if l >= 250 { tier = .blunder }
                else if l >= 120 { tier = .miss }
                else if l >= 60 { tier = .dubious }
                else { tier = .good }
            } else {
                tier = .unknown
            }
            out.append(ReviewedMove(ply: i, uci: uci, san: san, mover: mover,
                                    bestUci: bests[i], bestSan: bestSan,
                                    loss: loss, tier: tier))
            board.apply(mv)
            positions.append(board.squares)
        }

        let reviewed = out.filter { human == nil || $0.mover == human }
        let known = reviewed.compactMap(\.loss)
        let avg = known.isEmpty ? 0 : Double(known.reduce(0, +)) / Double(known.count)
        let accuracy = max(0, min(100, Int((100.0 * exp(-avg / 300.0)).rounded())))
        return GameReview(moves: out, positions: positions, accuracy: accuracy)
    }

    // MARK: - UCI matching & SAN

    /// Rebuild a ChessMove from UCI ("e2e4", "e7e8q") against legal moves.
    static func matchUci(_ uci: String, on board: ChessBoard) -> ChessMove? {
        let files = Array("abcdefgh")
        let chars = Array(uci.lowercased())
        guard chars.count >= 4,
              let ff = files.firstIndex(of: chars[0]),
              let tf = files.firstIndex(of: chars[2]),
              let fr = chars[1].wholeNumberValue, (1...8).contains(fr),
              let tr = chars[3].wholeNumberValue, (1...8).contains(tr) else {
            return nil
        }
        let from = Square.make(file: ff, rank: fr - 1)
        let to = Square.make(file: tf, rank: tr - 1)
        var promotion: PieceType? = nil
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

    /// Compact SAN ("Nbd7", "exd8=Q+", "O-O#"). Correct (if plain) — full
    /// disambiguation via the legal move list.
    static func sanString(for move: ChessMove, on board: ChessBoard, legal: [ChessMove]) -> String {
        guard let piece = board.squares[move.from] else { return move.uci }
        if move.isCastleKingside { return castleSuffix("O-O", move: move, on: board) }
        if move.isCastleQueenside { return castleSuffix("O-O-O", move: move, on: board) }
        var s = ""
        let isCapture = move.isCapture
        if piece.type == .pawn {
            // "e4", or "exd5" for a capture.
            if isCapture { s += String("abcdefgh"[Square.file(of: move.from)]) + "x" }
            s += Square.name(of: move.to)
            if let promo = move.promotion { s += "=\(promo.sanLetter)" }
        } else {
            s += piece.type.sanLetter
            // Disambiguate against same-type peers reaching the same square.
            let peers = legal.filter {
                $0.from != move.from && $0.to == move.to &&
                board.squares[$0.from]?.type == piece.type
            }
            if !peers.isEmpty {
                let myFile = Square.file(of: move.from), myRank = Square.rank(of: move.from)
                let sameFile = peers.contains { Square.file(of: $0.from) == myFile }
                let sameRank = peers.contains { Square.rank(of: $0.from) == myRank }
                if !sameFile {
                    s += String("abcdefgh"[myFile])
                } else if !sameRank {
                    s += String(myRank + 1)
                } else {
                    s += Square.name(of: move.from)
                }
            }
            if isCapture { s += "x" }
            s += Square.name(of: move.to)
        }
        // Check / mate suffix.
        var after = board
        after.apply(move)
        if after.isInCheck(after.turn) {
            s += after.legalMoves(for: after.turn).isEmpty ? "#" : "+"
        }
        return s
    }

    private static func castleSuffix(_ s: String, move: ChessMove, on board: ChessBoard) -> String {
        var after = board
        after.apply(move)
        if after.isInCheck(after.turn) {
            return s + (after.legalMoves(for: after.turn).isEmpty ? "#" : "+")
        }
        return s
    }
}

// MARK: - Helpers

extension PieceType {
    var sanLetter: String {
        switch self {
        case .pawn: return ""
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }
}

private extension String {
    subscript(i: Int) -> Character { self[index(startIndex, offsetBy: i)] }
}
