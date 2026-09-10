// GnuChessBridge.mm — LocalChess
// See GnuChessBridge.h. Implements the pipe + pthread wiring around
// engine::main_engine (vendored GNU Chess, GPLv3).

#import "GnuChessBridge.h"

#import <pthread.h>
#import <unistd.h>
#import <sys/select.h>
#import <errno.h>
#import <string.h>

// Pipe file descriptors shared with src/engine (see gnuchess/components.h).
// Write end a2e[1] and read end e2a[0] belong to this bridge; the engine
// thread owns a2e[0] and e2a[1] via fdopen in main_engine.
int pipefd_a2e[2] = {-1, -1};
int pipefd_e2a[2] = {-1, -1};

namespace engine {
int main_engine(int argc, char *argv[]);
}

static void *EngineThreadEntry(void *) {
    engine::main_engine(0, nullptr);
    return nullptr;
}

@implementation GnuChessBridge {
    pthread_t _thread;
    BOOL _started;
    NSLock *_lock;
    NSMutableData *_readBuf;
}

- (instancetype)init {
    if ((self = [super init])) {
        _lock = [[NSLock alloc] init];
        _readBuf = [[NSMutableData alloc] init];
    }
    return self;
}

// MARK: - Raw IO (caller holds _lock)

- (BOOL)writeLine:(NSString *)line {
    NSString *withNewline = [line stringByAppendingString:@"\n"];
    const char *bytes = [withNewline UTF8String];
    size_t left = strlen(bytes);
    while (left > 0) {
        ssize_t w = write(pipefd_a2e[1], bytes + (strlen(bytes) - left), left);
        if (w <= 0) return NO;
        left -= (size_t)w;
    }
    return YES;
}

/// Blocking line read with a timeout. Returns nil on timeout, EOF, or error.
/// Leftover bytes stay buffered for the next call.
- (nullable NSString *)readLineWithTimeout:(NSTimeInterval)timeout {
    for (;;) {
        const char *buf = (const char *)_readBuf.bytes;
        NSUInteger len = _readBuf.length;
        for (NSUInteger i = 0; i < len; i++) {
            if (buf[i] == '\n') {
                NSString *line = [[NSString alloc] initWithBytes:buf
                                                          length:i
                                                        encoding:NSUTF8StringEncoding];
                [_readBuf replaceBytesInRange:NSMakeRange(0, i + 1) withBytes:NULL length:0];
                return [line stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        }
        fd_set set;
        FD_ZERO(&set);
        FD_SET(pipefd_e2a[0], &set);
        struct timeval tv;
        tv.tv_sec = (int)timeout;
        tv.tv_usec = (int)((timeout - tv.tv_sec) * 1000000);
        int ready = select(pipefd_e2a[0] + 1, &set, NULL, NULL, &tv);
        if (ready <= 0) return nil; // timeout or error
        char tmp[4096];
        ssize_t n = read(pipefd_e2a[0], tmp, sizeof(tmp));
        if (n <= 0) return nil; // EOF or error: engine is gone
        [_readBuf appendBytes:tmp length:(NSUInteger)n];
    }
}

/// Sends cmd (unless nil) then reads lines until one starts with marker.
/// Returns the full marker line, or nil on timeout/failure. "info" chatter
/// is skipped; everything else unexpected also ends the wait as failure-safe.
- (nullable NSString *)transact:(nullable NSString *)cmd
                    untilMarker:(NSString *)marker
                        timeout:(NSTimeInterval)timeout {
    if (cmd && ![self writeLine:cmd]) return nil;
    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + timeout;
    for (;;) {
        NSTimeInterval left = deadline - [NSDate timeIntervalSinceReferenceDate];
        if (left <= 0) return nil;
        NSString *line = [self readLineWithTimeout:left];
        if (!line) return nil;
        if ([line hasPrefix:marker]) return line;
        // Skip "info ..." and anything else; keep waiting for the marker.
    }
}

// MARK: - Public API

- (BOOL)started {
    [_lock lock];
    BOOL s = _started;
    [_lock unlock];
    return s;
}

- (BOOL)start {
    [_lock lock];
    @try {
        if (_started) return YES;
        if (pipe(pipefd_a2e) != 0 || pipe(pipefd_e2a) != 0) return NO;
        if (pthread_create(&_thread, NULL, EngineThreadEntry, NULL) != 0) {
            return NO;
        }
        // Handshake: the engine boots (tables, hash) then answers UCI.
        if (![self transact:@"uci" untilMarker:@"uciok" timeout:30.0]) return NO;
        // No opening book is bundled; play bookless rather than fail on it.
        if (![self writeLine:@"setoption name OwnBook value false"]) return NO;
        if (![self writeLine:@"setoption name Hash value 32"]) return NO;
        if (![self transact:@"isready" untilMarker:@"readyok" timeout:30.0]) return NO;
        _started = YES;
        return YES;
    } @finally {
        [_lock unlock];
    }
}

- (nullable NSString *)bestMoveWithMoves:(NSArray<NSString *> *)moves
                              movetimeMs:(NSInteger)ms {
    [_lock lock];
    @try {
        if (!_started) return nil;
        NSString *position = @"position startpos";
        if (moves.count > 0) {
            position = [position stringByAppendingFormat:@" moves %@",
                        [moves componentsJoinedByString:@" "]];
        }
        if (![self writeLine:position]) return nil;
        NSString *go = [NSString stringWithFormat:@"go movetime %ld", (long)ms];
        // Generous margin over movetime so slow devices never truncate search.
        NSString *reply = [self transact:go untilMarker:@"bestmove"
                                        timeout:(ms / 1000.0) + 30.0];
        if (!reply) return nil;
        NSArray<NSString *> *parts = [reply componentsSeparatedByString:@" "];
        if (parts.count < 2) return nil;
        return parts[1];
    } @finally {
        [_lock unlock];
    }
}

- (void)sendNewGame {
    [_lock lock];
    @try {
        if (_started) [self writeLine:@"ucinewgame"];
    } @finally {
        [_lock unlock];
    }
}

@end
