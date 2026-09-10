// GnuChessBridge.h — LocalChess
// Bridge to the vendored GNU Chess engine (GPLv3, see gnuchess/COPYING).
// The engine runs on its own pthread and speaks UCI over two POSIX pipes,
// exactly like the upstream components wiring, minus frontend and adapter:
// this app writes commands to pipefd_a2e[1] and reads replies from
// pipefd_e2a[0]. All methods are thread-safe (single lock) but synchronous,
// so callers must stay off the main thread. Engine lifetime = process
// lifetime; "quit" is never sent.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GnuChessBridge : NSObject

/// Starts the engine thread and performs the UCI handshake. Idempotent.
/// Returns NO if the engine could not be started or did not answer.
- (BOOL)start;

- (BOOL)started;

/// Sends "position startpos [moves ...]" + "go movetime ms", blocks until
/// the engine replies "bestmove", and returns the move in UCI coordinate
/// notation (e.g. "e2e4", "e7e8q"), or nil on timeout/failure.
- (nullable NSString *)bestMoveWithMoves:(NSArray<NSString *> *)moves
                              movetimeMs:(NSInteger)ms;

/// Sends "ucinewgame" (clears the transposition table). No reply expected.
- (void)sendNewGame;

@end

NS_ASSUME_NONNULL_END
