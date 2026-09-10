// ArasanBridge.h — LocalChess
// Bridge to the vendored Arasan chess engine (MIT, see arasan/LICENSE).
// The engine runs on its own pthread and speaks UCI over two POSIX pipes:
// std::cin/std::cout inside the engine thread are dup2'ed onto the pipes,
// so the app writes commands to pipefd_a2e[1] and reads replies from
// pipefd_e2a[0]. All methods are thread-safe (single lock) but synchronous,
// so callers must stay off the main thread. Engine lifetime = process
// lifetime; "quit" is never sent.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ArasanBridge : NSObject

/// Starts the engine thread and performs the UCI handshake. Idempotent.
/// Returns NO if the engine could not be started or did not answer.
- (BOOL)start;

- (BOOL)started;

/// Sends "position startpos [moves ...]" + "go movetime ms", blocks until
/// the engine replies "bestmove", and returns the move in UCI coordinate
/// notation (e.g. "e2e4", "e7e8q"), or nil on timeout/failure.
- (nullable NSString *)bestMoveWithMoves:(NSArray<NSString *> *)moves
                              movetimeMs:(NSInteger)ms;

/// Caps playing strength via UCI_LimitStrength/UCI_Elo. Pass limited=NO
/// for full strength.
- (void)configureStrengthWithElo:(NSInteger)elo limited:(BOOL)limited;

/// Sends "ucinewgame" (clears the transposition table). No reply expected.
- (void)sendNewGame;

@end

NS_ASSUME_NONNULL_END
