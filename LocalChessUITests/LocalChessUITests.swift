// LocalChessUITests.swift — board input regression tests.
// The board takes touches through one gesture and maps them to squares with
// BoardOrientation. These tests tap and drag squares by accessibility id and
// check what the board does: the right piece selected, moves played by
// tap-tap and by drag-and-drop, illegal drops undone, promotion asked for.
// Every launch passes -LCFresh, so a saved game never leaks into a test.

import XCTest

final class LocalChessUITests: XCTestCase {
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    func testTapSelectsCorrectSquare() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-LCFresh"]
        app.launch()
        XCTAssertTrue(el(app, "sq-e2").waitForExistence(timeout: 20))

        // Tapping the e-pawn must show exactly its moves.
        el(app, "sq-e2").tap()
        XCTAssertTrue(el(app, "dot-e3").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "dot-e4").exists)

        // Re-tapping elsewhere must move selection (and dots) with it.
        el(app, "sq-g1").tap()
        XCTAssertTrue(el(app, "dot-f3").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "dot-h3").exists)
        XCTAssertFalse(el(app, "dot-e4").exists)
        XCTAssertFalse(el(app, "dot-e3").exists)
    }

    func testPawnMoveAppliesAndEngineReplies() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-LCFresh"]
        app.launch()
        XCTAssertTrue(el(app, "sq-e2").waitForExistence(timeout: 20))

        el(app, "sq-e2").tap()
        XCTAssertTrue(el(app, "dot-e4").waitForExistence(timeout: 5))
        el(app, "sq-e4").tap()

        // The move must apply and the engine must reply (undo re-enables
        // only after a full round trip: history non-empty, engine idle).
        let undo = el(app, "undo")
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: undo, handler: nil)
        waitForExpectations(timeout: 30)
    }

    /// Taps computed from the board's own frame (where squares are VISUALLY
    /// rendered), not from each cell's accessibility frame, so any drift
    /// between visuals and tap targets fails loudly.
    func testVisualCenterTapsHitCorrectSquares() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-LCFresh"]
        app.launch()
        let board = el(app, "board")
        XCTAssertTrue(board.waitForExistence(timeout: 20))

        func tapCell(col dc: Double, row dr: Double) {
            board.coordinate(withNormalizedOffset: CGVector(dx: (dc + 0.5) / 8.0, dy: (dr + 0.5) / 8.0)).tap()
        }

        // Visual e2 (col 4, row 6 white-at-bottom) must show pawn dots.
        tapCell(col: 4, row: 6)
        XCTAssertTrue(el(app, "dot-e3").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "dot-e4").exists)

        // Visual g1 knight (col 6, row 7) must take over selection.
        tapCell(col: 6, row: 7)
        XCTAssertTrue(el(app, "dot-f3").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "dot-h3").exists)
        XCTAssertFalse(el(app, "dot-e4").exists)
    }

    /// Selecting a piece must not move it.
    func testSelectionDoesNotMovePiece() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-LCFresh"]
        app.launch()
        let board = el(app, "board")
        XCTAssertTrue(board.waitForExistence(timeout: 20))
        board.coordinate(withNormalizedOffset: CGVector(dx: 4.5 / 8.0, dy: 6.5 / 8.0)).tap()
        XCTAssertTrue(el(app, "dot-e4").waitForExistence(timeout: 5))
        XCTAssertTrue(((el(app, "sq-e2").value as? String) ?? "").contains("white pawn"))
        XCTAssertFalse(((el(app, "sq-e3").value as? String) ?? "").contains("pawn"))
    }

    /// Points are one cumulative running total: Scholar's mate in local
    /// 2-player mode scores Qxf7 (+1 pawn) + mate (+25) = 26, undo drops
    /// exactly the mate back off, and redo restores without double-counting.
    func testScholarsMateCumulativePoints() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-LCFresh"]
        app.launch()
        XCTAssertTrue(el(app, "sq-e2").waitForExistence(timeout: 20))

        // Local 2-player: fully deterministic, no engine.
        el(app, "menu").tap()
        let toggle = el(app, "vsEngineToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        Thread.sleep(forTimeInterval: 0.5)
        // A bare row tap sometimes lands on the label: hit the switch itself.
        let toggleValue = toggle.value as? String
        if toggleValue != "0" && toggleValue != "false" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(
            (toggle.value as? String) == "0" || (toggle.value as? String) == "false",
            "coach toggle would not switch off"
        )
        el(app, "startGame").tap()
        XCTAssertTrue(app.staticTexts["2 players · local"].waitForExistence(timeout: 5),
                      "game did not enter 2-player mode")

        // 1.e4 e5 2.Qh5 Nc6 3.Bc4 Nf6 4.Qxf7#
        let moves = [
            ("sq-e2", "sq-e4"), ("sq-e7", "sq-e5"),
            ("sq-d1", "sq-h5"), ("sq-b8", "sq-c6"),
            ("sq-f1", "sq-c4"), ("sq-g8", "sq-f6"),
            ("sq-h5", "sq-f7")
        ]
        for (from, to) in moves {
            el(app, from).tap()
            Thread.sleep(forTimeInterval: 0.2)
            el(app, to).tap()
            Thread.sleep(forTimeInterval: 0.3)
        }

        func pillText() -> String {
            app.staticTexts
                .containing(NSPredicate(format: "label CONTAINS 'POINTS'"))
                .firstMatch.label
        }
        XCTAssertTrue(app.staticTexts["26 POINTS"].waitForExistence(timeout: 10),
                      "pill shows: \(pillText())")

        // Dismiss the mate card, undo the mate, redo it.
        el(app, "continueButton").tap()
        el(app, "undo").tap()
        XCTAssertTrue(app.staticTexts["0 POINTS"].waitForExistence(timeout: 5))
        el(app, "redo").tap()
        XCTAssertTrue(app.staticTexts["26 POINTS"].waitForExistence(timeout: 5))
    }

    /// The coach bubble shows the yeti thinking portrait by default, proving
    /// the asset catalog images resolve at runtime.
    func testYetiCoachPortraitLoads() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-LCFresh"]
        app.launch()
        XCTAssertTrue(el(app, "coach-yeti-thinking").waitForExistence(timeout: 20))
    }

    /// Post-game review: Fool's mate in local 2-player mode (1.f3 e5 2.g4
    /// Qh4#), then REVIEW GAME grades the moves — g4 must be flagged a
    /// blunder and the replay stepper must scrub the game.
    func testReviewGradesBlunders() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-LCFresh"]
        app.launch()
        XCTAssertTrue(el(app, "sq-e2").waitForExistence(timeout: 20))

        el(app, "menu").tap()
        let toggle = el(app, "vsEngineToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        Thread.sleep(forTimeInterval: 0.5)
        let toggleValue = toggle.value as? String
        if toggleValue != "0" && toggleValue != "false" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        el(app, "startGame").tap()
        XCTAssertTrue(app.staticTexts["2 players · local"].waitForExistence(timeout: 5))

        for (from, to) in [("sq-f2", "sq-f3"), ("sq-e7", "sq-e5"),
                           ("sq-g2", "sq-g4"), ("sq-d8", "sq-h4")] {
            el(app, from).tap()
            Thread.sleep(forTimeInterval: 0.2)
            el(app, to).tap()
            Thread.sleep(forTimeInterval: 0.3)
        }

        el(app, "reviewGameButton").tap()
        // Engine grades ~5 positions at 400ms each; allow a wide margin.
        XCTAssertTrue(el(app, "yeti-score").waitForExistence(timeout: 120))
        // g4 (ply 2) hangs mate in one: must wear the blunder badge.
        XCTAssertTrue(el(app, "tier-Blunder-2").waitForExistence(timeout: 10))
        // Scrub to the final position and back via the stepper.
        el(app, "review-move-3").tap()
        XCTAssertTrue(app.staticTexts["4 / 4"].waitForExistence(timeout: 5))
    }

    /// Playing as Black rotates the board 180 degrees: Black's home rank
    /// renders at the bottom. The old mirror bug kept White at the bottom,
    /// which these frame + tap assertions catch.
    func testPlayAsBlackPutsBlackAtBottom() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-LCFresh"]
        app.launch()
        XCTAssertTrue(el(app, "sq-e2").waitForExistence(timeout: 20))

        el(app, "menu").tap()
        XCTAssertTrue(el(app, "startGame").waitForExistence(timeout: 5))
        el(app, "Black").tap()
        el(app, "startGame").tap()

        // Engine (White) moves first; wait until it hands over Black's move.
        XCTAssertTrue(app.staticTexts["Your move — Black"].waitForExistence(timeout: 30))

        let board = el(app, "board")
        let midY = board.frame.midY
        // Black pawn e7 sits in the bottom half, White pawn e2 in the top.
        XCTAssertGreaterThan(el(app, "sq-e7").frame.midY, midY, "e7 not at bottom")
        XCTAssertLessThan(el(app, "sq-e2").frame.midY, midY, "e2 not at top")

        // Visual cell (col 3, row 6) is e7 under a 180-degree rotation:
        // tapping it must select the Black pawn (dots on e6/e5).
        board.coordinate(withNormalizedOffset: CGVector(dx: 3.5 / 8.0, dy: 6.5 / 8.0)).tap()
        XCTAssertTrue(el(app, "dot-e6").waitForExistence(timeout: 5))
        XCTAssertTrue(el(app, "dot-e5").exists)
    }

    // MARK: Drag and drop, promotion

    private func twoPlayer(_ app: XCUIApplication) {
        el(app, "menu").tap()
        let toggle = el(app, "vsEngineToggle")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        Thread.sleep(forTimeInterval: 0.5)
        let v = toggle.value as? String
        if v != "0" && v != "false" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        el(app, "startGame").tap()
        XCTAssertTrue(app.staticTexts["2 players · local"].waitForExistence(timeout: 5))
    }

    private func drag(_ app: XCUIApplication, _ from: String, _ to: String) {
        el(app, from).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.15, thenDragTo: el(app, to).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func value(_ app: XCUIApplication, _ id: String) -> String {
        (el(app, id).value as? String) ?? ""
    }

    /// Dragging a piece to a legal square plays the move; to an illegal one,
    /// the piece goes back where it was.
    func testDragAndDrop() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-LCFresh"]
        app.launch()
        XCTAssertTrue(el(app, "sq-e2").waitForExistence(timeout: 20))
        twoPlayer(app)

        drag(app, "sq-g1", "sq-g3")  // not a knight move
        XCTAssertTrue(value(app, "sq-g1").contains("white knight"), "knight left g1 on an illegal drop")
        XCTAssertFalse(value(app, "sq-g3").contains("knight"))

        drag(app, "sq-g1", "sq-f3")
        XCTAssertTrue(value(app, "sq-f3").contains("white knight"), "drag to f3 didn't move the knight")
        XCTAssertFalse(value(app, "sq-g1").contains("knight"))
        XCTAssertTrue(app.staticTexts["Black to move"].waitForExistence(timeout: 5))

        drag(app, "sq-e7", "sq-e5")
        XCTAssertTrue(value(app, "sq-e5").contains("black pawn"))
        XCTAssertTrue(app.staticTexts["White to move"].waitForExistence(timeout: 5))
    }

    /// A pawn reaching the last rank asks which piece it becomes, on the board.
    func testPromotionPicker() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-LCFresh"]
        app.launch()
        XCTAssertTrue(el(app, "sq-e2").waitForExistence(timeout: 20))
        twoPlayer(app)

        // 1.h4 g5 2.hxg5 h6 3.gxh6 Bg7 4.hxg7 Nf6 5.gxh8
        let moves = [("h2", "h4"), ("g7", "g5"), ("h4", "g5"), ("h7", "h6"), ("g5", "h6"),
                     ("f8", "g7"), ("h6", "g7"), ("g8", "f6"), ("g7", "h8")]
        for (from, to) in moves {
            el(app, "sq-" + from).tap()
            Thread.sleep(forTimeInterval: 0.2)
            el(app, "sq-" + to).tap()
            Thread.sleep(forTimeInterval: 0.35)
        }
        XCTAssertTrue(el(app, "promote-knight").waitForExistence(timeout: 5), "no promotion picker")
        el(app, "promote-knight").tap()
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertTrue(value(app, "sq-h8").contains("white knight"), "h8 is \(value(app, "sq-h8"))")
        XCTAssertFalse(el(app, "promote-queen").exists)
    }
}
