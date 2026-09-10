// LocalChessUITests.swift — regression tests for tap-to-square mapping.
// Bug: taps used to land ~1 row off because a board-level DragGesture
// interpreted touches in the wrong coordinate space. Squares now handle
// their own taps; these tests tap squares by accessibility id and assert
// the dots follow the actual tapped square.

import XCTest

final class LocalChessUITests: XCTestCase {
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id]
    }

    func testTapSelectsCorrectSquare() throws {
        let app = XCUIApplication()
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
        app.launch()
        XCTAssertTrue(el(app, "coach-yeti-thinking").waitForExistence(timeout: 20))
    }

    /// Playing as Black rotates the board 180 degrees: Black's home rank
    /// renders at the bottom. The old mirror bug kept White at the bottom,
    /// which these frame + tap assertions catch.
    func testPlayAsBlackPutsBlackAtBottom() throws {
        let app = XCUIApplication()
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
}
