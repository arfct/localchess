// no_setrlimit.h — LocalChess (ours, not upstream)
// Force-included ONLY into Arasan's globals.cpp (per-file COMPILER_FLAGS).
// initGlobals() raises RLIMIT_STACK via setrlimit() and calls exit(-1) when
// the sandbox denies it — which iOS always does, killing the app at engine
// boot. The engine doesn't need it: search threads get explicit 4MB stacks
// via pthread_attr_setstacksize (allowed), and the main protocol thread is
// shallow. So we report a large stack limit and skip the setrlimit+exit.

#pragma once

#include <sys/resource.h>

static inline int __lc_fake_getrlimit(int who, struct rlimit *rlp) {
    if (who == RLIMIT_STACK) {
        rlp->rlim_cur = rlp->rlim_max = (rlim_t)(64ULL * 1024 * 1024);
        return 0;
    }
    extern int getrlimit(int, struct rlimit *);
    return getrlimit(who, rlp);
}

#define getrlimit __lc_fake_getrlimit
