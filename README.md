# LocalChess

An offline, Duolingo-style chess game for iOS. Play as White or Black against
a local engine, or play two-player on one phone. No network access required —
there is no networking code in the target at all.

The look and feel follows the reference screen recording
(`ScreenRecording_09-08-2026 22-59-31_1.MP4`): dark theme, yeti coach
character with speech-bubble quips, countdown timer + points pills, chunky
cute pieces, gold last-move highlight, legal-move dots, undo/redo buttons,
and a Checkmate! card with SHOW IT OFF / CONTINUE.

## Engine (actual GNU Chess)

- The opponent is the real GNU Chess 6.2.5 engine, vendored as C++ under
  `LocalChess/gnuchess/engine` (from https://github.com/madnight/gnuchess)
  and linked directly into the app — no separate binary, no network.
  It runs on its own pthread and speaks UCI over two POSIX pipes via
  `GnuChessBridge` (`LocalChess/gnuchess/GnuChessBridge.{h,mm}`); only the
  engine core is compiled (no frontend/adapter processes, no stdin/stdout
  tricks — iOS forbids spawning processes, threads + pipes are used
  instead). Think time per difficulty: Chill 250ms / Clever 800ms /
  Beast 2500ms (`go movetime`), 32MB hash, no opening book.
- Every engine reply is validated against our own legal move generator
  before it is played, and any engine failure falls back to the built-in
  `LocalSearchEngine` in `LocalChess/GnuChessEngine.swift` (alpha-beta +
  piece-square tables), so the game can never get stuck without a move.
- The rules core lives in `LocalChess/ChessCore.swift`: full legal move
  generation (castling, en passant, promotion), check / checkmate /
  stalemate, 50-move and insufficient-material draws. Verified with perft:
  20 / 400 / 8902 from the start position, plus Fool's-mate detection.

## License note (GPLv3)

Linking GNU Chess makes the app a derivative work under the GNU General
Public License v3 or later (see `LocalChess/gnuchess/COPYING`). That is
fine for personal use and sideloaded development builds, but the App
Store's DRM terms conflict with GPLv3, so do not ship this to the App
Store without resolving that (e.g. swapping the engine).

## Credits

- Piece artwork: the Cburnett chess set by Colin M.L. Burnett, via Wikimedia
  Commons (mirrored by lichess), multi-licensed under GFDL / BSD / GPL and
  used here under the BSD license. The SVGs are bundled in
  `LocalChess/Assets.xcassets`, so the app renders them offline.
- Coach portraits: custom yeti artwork bundled as `yeti-*` imagesets in
  `LocalChess/Assets.xcassets` (thinking / happy / excited / worried / sad /
  defeated), swapped by game mood.

## Haptics

All through `HapticManager` (`LocalChess/Haptics.swift`, CoreHaptics with
UIKit fallbacks; no-ops on simulator):

| Event | Feel |
|---|---|
| Move | light tick |
| Select piece | selection tick |
| Capture | heavy blast |
| Queen capture | extra-crazy multi-burst + rumble |
| Check | triple alarm pulse + red pulsing glow + king shake |
| Checkmate (win) | escalating celebration pattern + confetti |
| Checkmate (loss) | long heavy error buzz |

## Animations

- Pieces slide square-to-square (stable piece IDs + spring animation).
- Captures pop out with scale + fade; queen captures also fire confetti-grade haptics.
- Check: pulsing red glow + shake on the king, CHECK! badge.
- Checkmate: confetti rain + Checkmate! card with mini-board snapshot.
- Selection bounce, last-move gold tint, legal-move dots.

## Build & run

Requirements: Xcode 16+, iOS 17 SDK.

```sh
open LocalChess.xcodeproj
# pick an iPhone simulator and press Run
```

Headless build:

```sh
xcodebuild -project LocalChess.xcodeproj -scheme LocalChess \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Game controls: tap ✕ (top left) for a new game — choose White / Black /
2-player and yeti strength. Undo/redo buttons sit at the bottom like the
reference. Timer is 15:00; flagging loses the game. Points: 1/3/3/5/9 per
captured pawn/knight/bishop/rook/queen, +2 for giving check, +25 for mate.

## Tests

UI regression suite (`LocalChessUITests`, 7 tests: tap-to-square mapping,
visual-center taps, engine reply round trip, cumulative Scholar's-mate
points with undo/redo, play-as-Black 180° rotation, yeti portrait load):

```sh
xcodebuild -project LocalChess.xcodeproj -scheme LocalChess \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

## Signing (your own device)

The project is set up for development sideloading. To run on your iPhone,
open the project in Xcode and, under Signing & Capabilities, select your
own Apple Developer team and a unique bundle identifier — no other code
changes needed. Everything else (engine, art, tests) builds offline.
