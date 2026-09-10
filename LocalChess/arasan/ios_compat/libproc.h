// libproc.h — LocalChess (ours, not upstream)
// iOS shim: the macOS <libproc.h> header does not exist in the iOS SDK, but
// Arasan's globals.cpp includes it under _MAC for proc_pidpath() (used to
// locate the NNUE network next to the app binary). This header provides a
// compatible proc_pidpath() built on _NSGetExecutablePath(). It is found via
// HEADER_SEARCH_PATHS and only affects the vendored Arasan sources.

#pragma once

// From macOS <sys/proc_info.h> (absent on iOS); sizes the path buffer in
// Arasan's globals.cpp.
#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 1024
#endif

#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <mach-o/dyld.h>

static inline int proc_pidpath(int pid, char *buffer, uint32_t buffersize) {
    (void)pid;
    uint32_t size = buffersize;
    if (_NSGetExecutablePath(buffer, &size) != 0) return 0;
    return (int)strlen(buffer);
}
