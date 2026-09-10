/* components.h — LocalChess minimal version.
   Upstream components.h/components.cc wire up frontend, adapter and engine
   threads. This app drives the engine thread directly over UCI, so only the
   pipe file descriptors shared with src/engine are needed here. The app's
   bridge creates the pipes and starts the engine thread; no frontend or
   adapter code is compiled. */

#ifndef GNUCHESS_IOS_COMPONENTS_H
#define GNUCHESS_IOS_COMPONENTS_H

/* File descriptors for the pipes used to communicate with the engine. */

extern int pipefd_a2e[2];

extern int pipefd_e2a[2];

#endif /* GNUCHESS_IOS_COMPONENTS_H */
