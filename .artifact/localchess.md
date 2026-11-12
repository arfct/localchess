---
title: LocalChess
date: 2026-09
status: wip
category: product
tags: [ios, game]
url: https://github.com/arfct/localchess
links:
  source: https://github.com/arfct/localchess
media:
  - src: two-displays.png
    caption: The same position on an iPhone, left, and on the outer display of an iPhone Duo, where the clock and battery sit in a strip beside the board
    alt: Two dark phone screens side by side, each with a chessboard in mid-game under a yeti portrait and a speech bubble, a red pill reading -3 points and a green New Game button
  - src: game.png
    caption: Six moves into a game against the yeti at its Clever strength, with Black's last move tinted gold and the score at minus three
    alt: A phone screen with a dark chessboard in mid-game under a yeti portrait and a speech bubble reading Fresh snow! Come test the Yeti, a red pill reading -3 points, a green clock at 14:05 and a New Game button
credits: [dps]
unconfirmed: [date, status]
---

On a partly folded iPhone Duo, LocalChess keeps its board to one side of the fold. In the arrangement its code calls tabletop the board is on the half lying flat, with the coach and the move list on the raised half; in the one called book the board takes one page and the rest takes the other. Opened flat with two people playing, Black's strip and pieces turn to face across the table.

The coach is a yeti, and the opponent behind it is Arasan 26.0, Jon Dart's chess engine, compiled into the app at three strengths named Chill, Clever and Beast. Because iOS does not let an app start a second process, the engine runs on a thread of its own and is addressed over two pipes, and each of its replies is checked against the app's own move generator before it is played. The app contains no networking code.

In the images a game against Clever is six moves old. Captures score 1, 3, 3, 5 and 9 points by piece and count against the player when the yeti makes them, which is how the score has reached minus three for the loss of a bishop. After a game the engine goes back over it and grades every move. LocalChess is distributed as source under the MIT license.

Swift, SwiftUI, C++. 2026.
