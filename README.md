# LocalChess

An offline, Duolingo-style chess game for iOS. Play as White or Black against
a local engine, or play two-player on one phone. No network access required —
there is no networking code in the target at all.

The look and feel follows the reference screen recording
(`ScreenRecording_09-08-2026 22-59-31_1.MP4`): dark theme, yeti coach
character with speech-bubble quips, countdown timer + points pills, chunky
cute pieces, gold last-move highlight, legal-move dots, undo/redo buttons,
and a Checkmate! card with SHOW IT OFF / CONTINUE.

## Engine (actual Arasan)

- The opponent is the real Arasan 26.0 engine by Jon Dart, vendored as C++
  under `LocalChess/arasan/engine` (from https://github.com/jdart1/arasan-chess,
  MIT license — see `LocalChess/arasan/LICENSE`, NNUE network weights
  included) and linked directly into the app — no separate binary, no network.
  It runs on its own pthread and speaks UCI over two POSIX pipes via
  `ArasanBridge` (`LocalChess/arasan/ArasanBridge.{h,mm}`): stdin/stdout are
  dup2'ed onto the pipes in the engine thread (iOS forbids spawning
  processes). Only the engine core is compiled (no GUI, book, tablebase, or
  test tools). Think time per difficulty: Chill 250ms / Clever 800ms /
  Beast 2500ms (`go movetime`) plus UCI_Elo caps (1100 / 1700 / unlimited),
  32MB hash, single thread, no opening book.
- iOS specifics: compiled with `-D_MAC -DSIMD -DNEON`; the 25MB NNUE net
  ships inside the app bundle next to the binary so the engine finds it at
  startup. Two small shims in `LocalChess/arasan/ios_compat/` (ours, upstream
  untouched): `libproc.h` for the macOS-only `<libproc.h>` (proc_pidpath via
  dyld), and `no_setrlimit.h` force-included into `globals.cpp` — Arasan's
  startup raises RLIMIT_STACK and calls exit(-1) when the iOS sandbox denies
  it, which killed the app at engine boot; the shim reports a large limit so
  the call is skipped (search threads size their own stacks explicitly, which
  is allowed). The bridge also spawns the engine pthread with an 8MB stack.
- One-line change to vendored `engine/search.cpp` (`Search::reduce`): the
  LMR reduction total can go slightly negative, which Apple's hardened
  `std::clamp` aborts on (libstdc++ tolerates it) — the bound is floored at
  zero, matching the function's own "do not allow negative reduction"
  intent. Worth reporting upstream.
- Every engine reply is validated against our own legal move generator
  before it is played, and any engine failure falls back to the built-in
  `LocalSearchEngine` in `LocalChess/GnuChessEngine.swift` (alpha-beta +
  piece-square tables), so the game can never get stuck without a move.
- The rules core lives in `LocalChess/ChessCore.swift`: full legal move
  generation (castling, en passant, promotion), check / checkmate /
  stalemate, 50-move and insufficient-material draws. Verified with perft:
  20 / 400 / 8902 from the start position, plus Fool's-mate detection.

## License

MIT. Arasan (engine + network) is MIT-licensed by Jon Dart (see
`LocalChess/arasan/LICENSE`, attribution kept in the in-app menu); piece
art is BSD (see Credits); everything else is original to this repo.
No App Store conflict: unlike the previous GNU Chess engine, nothing here
is copyleft.

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

## iPhone Duo

The screen arranges itself for wherever the game is showing
(`LocalChess/GameLayout.swift`), and never puts the board across the fold:

| Where | Layout |
|---|---|
| iPhone, Duo outside display | one column: coach, the yeti's strip, board, your strip, controls |
| Duo tabletop | the board on the half lying flat, the strips and controls beside it; coach and move list on the raised half |
| Duo book | the board on one page, coach, strips and move list on the other |
| Duo open flat, portrait | a big board; with two players, Black's strip and pieces turn to face across the table |
| Any wide screen | the board as tall as the screen, a panel beside it |

The fold comes from SwiftUI's `reservedRegions(kind: .division)` (iOS
27.1+). To try the fold layouts without folding a phone, launch with
`-LCFold tabletop` or `-LCFold book`. The checkmate card stays on one half
too, in a compact form when that half is short.

## Moving pieces

One gesture over the board handles both ways of moving
(`LocalChess/BoardView.swift`):

- **Drag:** touch a piece and it lifts; drag it and it follows your finger
  from where you grabbed it, riding a little above it so your finger
  doesn't hide it, with the landing square ringed. Drop on a legal square to
  move, anywhere else and it slides home.
- **Tap:** tap a piece, then its destination. Tap it again to put it down.
- **Promotion:** the four choices open on the board from the promotion
  square; tap outside them to take the move back.

Each side has its own clock (none, 5, 10 or 15 minutes, chosen in the new
game sheet). Against the yeti only yours runs. Clocks start with the first
move. The game is saved after every move, so it survives the app closing.

## Animations

- Pieces slide square-to-square (stable piece IDs + spring animation).
- Captures pop out with scale + fade; queen captures also fire confetti-grade haptics.
- Check: pulsing red glow + shake on the king, CHECK! badge.
- Checkmate: confetti rain + Checkmate! card with mini-board snapshot.
- A picked-up piece lifts where it stands; last-move gold tint, legal-move dots.
- Move list in SAN, captured pieces and material lead for each side.

## Build & run

Requirements: Xcode 27+ (iOS 27.1 SDK, for the Duo's fold); runs on iOS 17+.

```sh
open LocalChess.xcodeproj
# pick an iPhone simulator and press Run
```

Headless build:

```sh
xcodebuild -project LocalChess.xcodeproj -scheme LocalChess \
  -sdk iphonesimulator -configuration Debug ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
```

(`ARCHS=arm64`: the engine's NEON code doesn't build for Intel simulators.)

Game controls: tap ✕ (top left) for a new game — choose White / Black /
2-player, yeti strength and clock. Undo/redo buttons sit at the bottom.
Flagging loses the game. Points: 1/3/3/5/9 per
captured pawn/knight/bishop/rook/queen, +2 for giving check, +25 for mate.

## Tests

UI regression suite (`LocalChessUITests`, 10 tests: tap-to-square mapping,
visual-center taps, engine reply round trip, cumulative Scholar's-mate
points with undo/redo, play-as-Black 180° rotation, yeti portrait load,
review grading, drag-and-drop with an illegal drop, on-board promotion):

```sh
xcodebuild -project LocalChess.xcodeproj -scheme LocalChess \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO test
```

## Signing (your own device)

The project is set up for development sideloading. To run on your iPhone,
open the project in Xcode and, under Signing & Capabilities, select your
own Apple Developer team and a unique bundle identifier — no other code
changes needed. Everything else (engine, art, tests) builds offline.
