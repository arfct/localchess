/* config.h — LocalChess iOS build configuration for the vendored
   GNU Chess engine (src/engine only; no frontend, no adapter).
   Replaces the autotools-generated config.h. Only VERSION is required
   (used by the UCI "id name" reply). ASSERTs stay disabled: engine/util.h
   enables its fatal ASSERT() only when DEBUG is defined, and the iOS
   project passes -DDEBUG=0 for these sources. */

#ifndef GNUCHESS_IOS_CONFIG_H
#define GNUCHESS_IOS_CONFIG_H

#define VERSION "6.2.5"
#define PACKAGE_NAME "GNU Chess"
#define PACKAGE_STRING "GNU Chess 6.2.5"
#define PACKAGE_VERSION "6.2.5"

#endif /* GNUCHESS_IOS_CONFIG_H */
