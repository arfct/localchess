// ArasanBridge.mm — LocalChess
// See ArasanBridge.h. Implements the pipe + pthread + dup2 wiring around
// arasan_main (vendored Arasan, MIT). arasanx.cpp is compiled with
// -Dmain=arasan_main so the engine entry links into the app binary.

#import "ArasanBridge.h"

#import <pthread.h>
#import <unistd.h>
#import <sys/select.h>
#import <errno.h>
#import <string.h>

// arasanx.cpp entry point (renamed via -Dmain=arasan_main).
int arasan_main(int argc, char *argv[]);

static int pipefd_a2e[2] = {-1, -1};
static int pipefd_e2a[2] = {-1, -1};

static void *EngineThreadEntry(void *) {
    // Route this process's stdin/stdout onto our pipes before Arasan
    // touches std::cin/std::cout. The app itself never uses fds 0/1
    // (logging goes to stderr), so claiming them is safe.
    dup2(pipefd_a2e[0], STDIN_FILENO);
    dup2(pipefd_e2a[1], STDOUT_FILENO);
    close(pipefd_a2e[0]);
    close(pipefd_e2a[1]);
    char *argv[] = {(char *)"arasan", (char *)"-c", (char *)"1",
                    (char *)"-H", (char *)"32", nullptr};
    arasan_main(5, argv);
    return nullptr;
}

/// Engine pthread with an 8MB stack: Arasan's own search threads size
/// themselves, but this entry thread runs all of startup (NNUE load,
/// tables) plus the UCI loop, so give it room.
static BOOL SpawnEngineThread(pthread_t *thread) {
    pthread_attr_t attr;
    if (pthread_attr_init(&attr) != 0) return NO;
    BOOL ok = NO;
    if (pthread_attr_setstacksize(&attr, 8 * 1024 * 1024) == 0 &&
        pthread_create(thread, &attr, EngineThreadEntry, NULL) == 0) {
        ok = YES;
    }
    pthread_attr_destroy(&attr);
    return ok;
}

@implementation ArasanBridge {
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
        if (!SpawnEngineThread(&_thread)) {
            return NO;
        }
        // Handshake: the engine boots (NNUE net, tables) then answers UCI.
        // The net ships next to the app binary so derivePath finds it.
        if (![self transact:@"uci" untilMarker:@"uciok" timeout:60.0]) return NO;
        // No opening book is bundled; play bookless rather than fail on it.
        if (![self writeLine:@"setoption name OwnBook value false"]) return NO;
        if (![self writeLine:@"setoption name Hash value 32"]) return NO;
        if (![self writeLine:@"setoption name Threads value 1"]) return NO;
        if (![self transact:@"isready" untilMarker:@"readyok" timeout:60.0]) return NO;
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
        if (parts.count < 2 || [parts[1] isEqualToString:@"(none)"]) return nil;
        return parts[1];
    } @finally {
        [_lock unlock];
    }
}

- (void)configureStrengthWithElo:(NSInteger)elo limited:(BOOL)limited {
    [_lock lock];
    @try {
        if (!_started) return;
        [self writeLine:[NSString stringWithFormat:@"setoption name UCI_LimitStrength value %@",
                         limited ? @"true" : @"false"]];
        if (limited) {
            [self writeLine:[NSString stringWithFormat:@"setoption name UCI_Elo value %ld",
                             (long)elo]];
        }
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
