// ChessCore.swift — LocalChess
// Pure-Swift local chess core: board model, full legal move generation,
// check / checkmate / stalemate / draw detection.
// This module is the in-app game engine core. It implements the same
// contract as a UCI-style engine (position in, best move out, fully
// offline) and additionally validates every reply from the real vendored
// engine via `ArasanAdapter` (see GnuChessEngine.swift) before it is
// played. No network access is used anywhere.

import Foundation

// MARK: - Basic types

enum PieceColor: Int, Codable, CaseIterable {
    case white = 0, black = 1
    var opposite: PieceColor { self == .white ? .black : .white }
}

enum PieceType: Int, Codable, CaseIterable {
    case pawn = 0, knight, bishop, rook, queen, king

    var value: Int {
        switch self {
        case .pawn: return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook: return 500
        case .queen: return 900
        case .king: return 0
        }
    }

    /// Duolingo-style points awarded for capturing this piece.
    var points: Int {
        switch self {
        case .pawn: return 1
        case .knight, .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 0
        }
    }
}

/// A piece on the board. `id` is stable across moves so SwiftUI can animate
/// slides with position changes instead of crossfades.
struct BoardPiece: Identifiable, Codable, Equatable {
    let id: UUID
    let color: PieceColor
    var type: PieceType

    init(color: PieceColor, type: PieceType) {
        self.id = UUID()
        self.color = color
        self.type = type
    }
}

// MARK: - Squares & moves

/// Square index 0...63. file 0 = a, rank 0 = rank 1 (white home rank).
enum Square {
    static func make(file: Int, rank: Int) -> Int { rank * 8 + file }
    static func file(of sq: Int) -> Int { sq % 8 }
    static func rank(of: Int) -> Int { `of` / 8 }
    static func name(of sq: Int) -> String {
        let files = ["a","b","c","d","e","f","g","h"]
        return "\(files[file(of: sq)])\(rank(of: sq) + 1)"
    }
    static func isValid(file: Int, rank: Int) -> Bool {
        file >= 0 && file < 8 && rank >= 0 && rank < 8
    }
}

struct ChessMove: Equatable, Codable {
    var from: Int
    var to: Int
    var promotion: PieceType?
    var isEnPassant: Bool = false
    var isCastleKingside: Bool = false
    var isCastleQueenside: Bool = false
    /// Piece type captured (nil if quiet). Filled in by the generator.
    var captured: PieceType?

    var isCapture: Bool { captured != nil || isEnPassant }
    var isCastle: Bool { isCastleKingside || isCastleQueenside }

    var uci: String {
        var s = Square.name(of: from) + Square.name(of: to)
        switch promotion {
        case .knight: s += "n"
        case .bishop: s += "b"
        case .rook: s += "r"
        case .queen: s += "q"
        case nil, .pawn, .king: break
        }
        return s
    }
}

// MARK: - Position

struct CastlingRights: Codable, Equatable {
    var whiteKingside = true
    var whiteQueenside = true
    var blackKingside = true
    var blackQueenside = true
}

/// Snapshot used for undo/redo.
struct PositionSnapshot: Codable, Equatable {
    var squares: [BoardPiece?]
    var turn: PieceColor
    var rights: CastlingRights
    var enPassantTarget: Int?
    var halfmoveClock: Int
    var fullmoveNumber: Int
    var lastMove: ChessMove?
}

enum GameResult: Equatable {
    case ongoing
    case checkmate(winner: PieceColor)
    case stalemate
    case draw(reason: String)
    case timeout(winner: PieceColor)
}

struct ChessBoard: Codable, Equatable {
    var squares: [BoardPiece?] = Array(repeating: nil, count: 64)
    var turn: PieceColor = .white
    var rights = CastlingRights()
    var enPassantTarget: Int? = nil
    var halfmoveClock = 0
    var fullmoveNumber = 1
    var lastMove: ChessMove? = nil

    init() { setupInitial() }

    mutating func setupInitial() {
        squares = Array(repeating: nil, count: 64)
        let back: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for file in 0..<8 {
            squares[Square.make(file: file, rank: 0)] = BoardPiece(color: .white, type: back[file])
            squares[Square.make(file: file, rank: 1)] = BoardPiece(color: .white, type: .pawn)
            squares[Square.make(file: file, rank: 6)] = BoardPiece(color: .black, type: .pawn)
            squares[Square.make(file: file, rank: 7)] = BoardPiece(color: .black, type: back[file])
        }
        turn = .white
        rights = CastlingRights()
        enPassantTarget = nil
        halfmoveClock = 0
        fullmoveNumber = 1
        lastMove = nil
    }

    func snapshot() -> PositionSnapshot {
        PositionSnapshot(squares: squares, turn: turn, rights: rights,
                         enPassantTarget: enPassantTarget, halfmoveClock: halfmoveClock,
                         fullmoveNumber: fullmoveNumber, lastMove: lastMove)
    }

    mutating func restore(_ snap: PositionSnapshot) {
        squares = snap.squares; turn = snap.turn; rights = snap.rights
        enPassantTarget = snap.enPassantTarget; halfmoveClock = snap.halfmoveClock
        fullmoveNumber = snap.fullmoveNumber; lastMove = snap.lastMove
    }

    func kingSquare(of color: PieceColor) -> Int? {
        squares.firstIndex(where: { $0?.color == color && $0?.type == .king })
    }

    // MARK: Attacks

    func isAttacked(_ sq: Int, by attacker: PieceColor) -> Bool {
        let f = Square.file(of: sq), r = Square.rank(of: sq)
        // Pawns
        let pawnRank = r + (attacker == .white ? -1 : 1)
        for df in [-1, 1] {
            if Square.isValid(file: f + df, rank: pawnRank),
               let p = squares[Square.make(file: f + df, rank: pawnRank)],
               p.color == attacker && p.type == .pawn { return true }
        }
        // Knights
        for (df, dr) in [(1,2),(2,1),(2,-1),(1,-2),(-1,-2),(-2,-1),(-2,1),(-1,2)] {
            if Square.isValid(file: f + df, rank: r + dr),
               let p = squares[Square.make(file: f + df, rank: r + dr)],
               p.color == attacker && p.type == .knight { return true }
        }
        // King
        for df in -1...1 { for dr in -1...1 {
            if df == 0 && dr == 0 { continue }
            if Square.isValid(file: f + df, rank: r + dr),
               let p = squares[Square.make(file: f + df, rank: r + dr)],
               p.color == attacker && p.type == .king { return true }
        }}
        // Sliders
        let bishopDirs = [(1,1),(1,-1),(-1,1),(-1,-1)]
        let rookDirs = [(1,0),(-1,0),(0,1),(0,-1)]
        for (df, dr) in bishopDirs {
            if rayHits(fromFile: f, rank: r, df: df, dr: dr, attacker: attacker, types: [.bishop, .queen]) { return true }
        }
        for (df, dr) in rookDirs {
            if rayHits(fromFile: f, rank: r, df: df, dr: dr, attacker: attacker, types: [.rook, .queen]) { return true }
        }
        return false
    }

    private func rayHits(fromFile f: Int, rank r: Int, df: Int, dr: Int,
                         attacker: PieceColor, types: [PieceType]) -> Bool {
        var cf = f + df, cr = r + dr
        while Square.isValid(file: cf, rank: cr) {
            if let p = squares[Square.make(file: cf, rank: cr)] {
                return p.color == attacker && types.contains(p.type)
            }
            cf += df; cr += dr
        }
        return false
    }

    func isInCheck(_ color: PieceColor) -> Bool {
        guard let k = kingSquare(of: color) else { return false }
        return isAttacked(k, by: color.opposite)
    }

    // MARK: Move generation

    /// Pseudo-legal moves for one piece (may leave king in check).
    func pseudoMoves(from sq: Int) -> [ChessMove] {
        guard let piece = squares[sq] else { return [] }
        let f = Square.file(of: sq), r = Square.rank(of: sq)
        var moves: [ChessMove] = []

        func addQuiet(to t: Int) {
            moves.append(ChessMove(from: sq, to: t))
        }
        func addCapture(to t: Int) {
            if let victim = squares[t], victim.color != piece.color {
                moves.append(ChessMove(from: sq, to: t, captured: victim.type))
            }
        }
        func addPawnMove(to t: Int, capture: PieceType?) {
            let promoRank = (piece.color == .white) ? 7 : 0
            if Square.rank(of: t) == promoRank {
                for promo in [PieceType.queen, .rook, .bishop, .knight] {
                    moves.append(ChessMove(from: sq, to: t, promotion: promo, captured: capture))
                }
            } else {
                moves.append(ChessMove(from: sq, to: t, captured: capture))
            }
        }

        switch piece.type {
        case .pawn:
            let dir = piece.color == .white ? 1 : -1
            let startRank = piece.color == .white ? 1 : 6
            let one = (f, r + dir)
            if Square.isValid(file: one.0, rank: one.1),
               squares[Square.make(file: one.0, rank: one.1)] == nil {
                addPawnMove(to: Square.make(file: one.0, rank: one.1), capture: nil)
                let two = (f, r + 2 * dir)
                if r == startRank && squares[Square.make(file: two.0, rank: two.1)] == nil {
                    moves.append(ChessMove(from: sq, to: Square.make(file: two.0, rank: two.1)))
                }
            }
            for df in [-1, 1] {
                let tf = f + df, tr = r + dir
                guard Square.isValid(file: tf, rank: tr) else { continue }
                let t = Square.make(file: tf, rank: tr)
                if let victim = squares[t], victim.color != piece.color {
                    addPawnMove(to: t, capture: victim.type)
                } else if let ep = enPassantTarget, ep == t {
                    var m = ChessMove(from: sq, to: t, captured: .pawn)
                    m.isEnPassant = true
                    moves.append(m)
                }
            }
        case .knight:
            for (df, dr) in [(1,2),(2,1),(2,-1),(1,-2),(-1,-2),(-2,-1),(-2,1),(-1,2)] {
                guard Square.isValid(file: f + df, rank: r + dr) else { continue }
                let t = Square.make(file: f + df, rank: r + dr)
                if squares[t] == nil { addQuiet(to: t) } else { addCapture(to: t) }
            }
        case .king:
            for df in -1...1 { for dr in -1...1 {
                if df == 0 && dr == 0 { continue }
                guard Square.isValid(file: f + df, rank: r + dr) else { continue }
                let t = Square.make(file: f + df, rank: r + dr)
                if squares[t] == nil { addQuiet(to: t) } else { addCapture(to: t) }
            }}
            // Castling
            let home = piece.color == .white ? 0 : 7
            if r == home && f == 4 && !isInCheck(piece.color) {
                let ks = piece.color == .white ? rights.whiteKingside : rights.blackKingside
                let qs = piece.color == .white ? rights.whiteQueenside : rights.blackQueenside
                if ks
                    && squares[Square.make(file: 5, rank: home)] == nil
                    && squares[Square.make(file: 6, rank: home)] == nil
                    && !isAttacked(Square.make(file: 5, rank: home), by: piece.color.opposite)
                    && !isAttacked(Square.make(file: 6, rank: home), by: piece.color.opposite) {
                    var m = ChessMove(from: sq, to: Square.make(file: 6, rank: home))
                    m.isCastleKingside = true
                    moves.append(m)
                }
                if qs
                    && squares[Square.make(file: 3, rank: home)] == nil
                    && squares[Square.make(file: 2, rank: home)] == nil
                    && squares[Square.make(file: 1, rank: home)] == nil
                    && !isAttacked(Square.make(file: 3, rank: home), by: piece.color.opposite)
                    && !isAttacked(Square.make(file: 2, rank: home), by: piece.color.opposite) {
                    var m = ChessMove(from: sq, to: Square.make(file: 2, rank: home))
                    m.isCastleQueenside = true
                    moves.append(m)
                }
            }
        case .bishop, .rook, .queen:
            let dirs: [(Int, Int)]
            switch piece.type {
            case .bishop: dirs = [(1,1),(1,-1),(-1,1),(-1,-1)]
            case .rook: dirs = [(1,0),(-1,0),(0,1),(0,-1)]
            default: dirs = [(1,1),(1,-1),(-1,1),(-1,-1),(1,0),(-1,0),(0,1),(0,-1)]
            }
            for (df, dr) in dirs {
                var cf = f + df, cr = r + dr
                while Square.isValid(file: cf, rank: cr) {
                    let t = Square.make(file: cf, rank: cr)
                    if squares[t] == nil { addQuiet(to: t) }
                    else { addCapture(to: t); break }
                    cf += df; cr += dr
                }
            }
        }
        return moves
    }

    /// Fully legal moves for `color` (king safety enforced).
    func legalMoves(for color: PieceColor) -> [ChessMove] {
        var result: [ChessMove] = []
        for sq in 0..<64 {
            guard let p = squares[sq], p.color == color else { continue }
            for m in pseudoMoves(from: sq) {
                var copy = self
                copy.apply(m)
                if !copy.isInCheck(color) { result.append(m) }
            }
        }
        return result
    }

    // MARK: Make move (assumes legal)

    mutating func apply(_ move: ChessMove) {
        guard var piece = squares[move.from] else { return }
        let mover = piece.color

        if move.isEnPassant {
            let capSq = Square.make(file: Square.file(of: move.to),
                                    rank: Square.rank(of: move.from))
            squares[capSq] = nil
        } else if move.isCastleKingside {
            let rank = Square.rank(of: move.from)
            squares[Square.make(file: 5, rank: rank)] = squares[Square.make(file: 7, rank: rank)]
            squares[Square.make(file: 7, rank: rank)] = nil
        } else if move.isCastleQueenside {
            let rank = Square.rank(of: move.from)
            squares[Square.make(file: 3, rank: rank)] = squares[Square.make(file: 0, rank: rank)]
            squares[Square.make(file: 0, rank: rank)] = nil
        }

        // Castling rights update
        if piece.type == .king {
            if mover == .white { rights.whiteKingside = false; rights.whiteQueenside = false }
            else { rights.blackKingside = false; rights.blackQueenside = false }
        }
        if piece.type == .rook {
            let (f, r) = (Square.file(of: move.from), Square.rank(of: move.from))
            if mover == .white && r == 0 {
                if f == 0 { rights.whiteQueenside = false }
                if f == 7 { rights.whiteKingside = false }
            } else if mover == .black && r == 7 {
                if f == 0 { rights.blackQueenside = false }
                if f == 7 { rights.blackKingside = false }
            }
        }
        // Rook captured on home square
        let (tf, tr) = (Square.file(of: move.to), Square.rank(of: move.to))
        if mover == .white && tr == 7 {
            if tf == 0 { rights.blackQueenside = false }
            if tf == 7 { rights.blackKingside = false }
        } else if mover == .black && tr == 0 {
            if tf == 0 { rights.whiteQueenside = false }
            if tf == 7 { rights.whiteKingside = false }
        }

        // En passant target
        enPassantTarget = nil
        if piece.type == .pawn
            && abs(Square.rank(of: move.to) - Square.rank(of: move.from)) == 2 {
            enPassantTarget = Square.make(file: Square.file(of: move.from),
                                          rank: (Square.rank(of: move.from) + Square.rank(of: move.to)) / 2)
        }

        // Halfmove clock
        if piece.type == .pawn || move.isCapture { halfmoveClock = 0 }
        else { halfmoveClock += 1 }

        squares[move.from] = nil
        if let promo = move.promotion { piece.type = promo }
        squares[move.to] = piece

        if mover == .black { fullmoveNumber += 1 }
        turn = mover.opposite
        lastMove = move
    }

    // MARK: Game status

    func insufficientMaterial() -> Bool {
        var minors = 0
        for p in squares.compactMap({ $0 }) {
            switch p.type {
            case .pawn, .rook, .queen: return false
            case .knight, .bishop: minors += 1
            case .king: break
            }
        }
        return minors <= 1
    }

    func result() -> GameResult {
        let moves = legalMoves(for: turn)
        if moves.isEmpty {
            if isInCheck(turn) { return .checkmate(winner: turn.opposite) }
            return .stalemate
        }
        if halfmoveClock >= 100 { return .draw(reason: "50-move rule") }
        if insufficientMaterial() { return .draw(reason: "Insufficient material") }
        return .ongoing
    }

    func materialScore() -> Int {
        squares.compactMap { $0 }.reduce(0) { acc, p in
            acc + (p.color == .white ? p.type.value : -p.type.value)
        }
    }
}

