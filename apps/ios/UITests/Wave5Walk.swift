import XCTest

/// Moves the wave 5 frame walks share: open a title, read some pages, come back.
@MainActor
extension XCTestCase {

    /// The cover on the shelf whose label starts with a title, scrolling for it.
    func coverNamed(_ title: String, in app: XCUIApplication) throws -> XCUIElement {
        let named = NSPredicate(format: "label BEGINSWITH %@", title)
        for _ in 0..<5 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        }
        hold(0.5)
        for _ in 0..<30 {
            let match = app.buttons.matching(named).allElementsBoundByIndex.first {
                $0.isHittable && $0.frame.midY > 150 && $0.frame.midY < app.frame.height - 110
            }
            if let match { return match }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
            hold(0.4)
        }
        shutter(app, named: "x-nocover")
        throw Wave5Failure.because("No cover on the shelf starts with \(title). Buttons: \(app.buttons.allElementsBoundByIndex.prefix(14).map(\.label))")
    }

    /// Opens a title from the Library shelf and lands on its page.
    func w5OpenPage(of title: String, in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        _ = app.buttons.matching(NSPredicate(format: "label CONTAINS ', '")).firstMatch
            .waitForExistence(timeout: 20)
        waitForTheShelfToSettle(in: app)
        try coverNamed(title, in: app).tap()
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(
                format: "label BEGINSWITH 'Read' OR label BEGINSWITH 'Continue' OR label BEGINSWITH 'Listen' OR label BEGINSWITH 'Download'"
            )).firstMatch.waitForExistence(timeout: 10),
            "The cover \(title) reached no publication page."
        )
        hold(1)
    }

    /// Reads forward `turns` pages in the open reader, then closes it.
    func readAndClose(turns: Int, in app: XCUIApplication) throws {
        let primary = try XCTUnwrap(
            app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable)
        )
        primary.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "No reader opened.")
        hold(2)
        for _ in 0..<turns {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            hold(1.2)
        }
        if !app.buttons["Close"].isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            hold(1)
        }
        app.buttons["Close"].tap()
        hold(1.5)
    }

    /// Turns to the end screen, steps back onto the last page, and closes the reader there.
    func readToLastPage(in app: XCUIApplication) throws {
        let primary = try XCTUnwrap(
            app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable)
        )
        primary.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "No reader opened.")
        hold(2)
        let back = app.buttons["Back to the last page"]
        for _ in 0..<14 where !back.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            hold(1.2)
        }
        XCTAssertTrue(back.waitForExistence(timeout: 5), "The reader never reached its end screen.")
        back.tap()
        hold(2)
        if !app.buttons["Close"].isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            hold(1)
        }
        app.buttons["Close"].tap()
        hold(1.5)
    }

    /// Turns fast, while the chrome is still up, and closes at once. A last page that is
    /// dwelt on becomes the end screen and a finished record, so the walk does not dwell.
    func readFast(turns: Int, in app: XCUIApplication) throws {
        let primary = try XCTUnwrap(
            app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable)
        )
        primary.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "No reader opened.")
        hold(1)
        for _ in 0..<turns {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            hold(0.45)
        }
        app.buttons["Close"].tap()
        hold(1.5)
    }

    /// A tab, after scrolling back up if the floating tab bar folded away.
    func w5Tab(_ name: String, in app: XCUIApplication) throws {
        for _ in 0..<4 {
            if app.tabBars.buttons[name].exists, app.tabBars.buttons[name].isHittable {
                app.tabBars.buttons[name].tap()
                return
            }
            app.swipeDown()
            hold(0.6)
        }
        // A folded tab bar is one round control at the leading foot. Opening it lists the tabs.
        let folded = app.buttons.matching(NSPredicate(format: "label == 'Library' AND value == 'Collapsed'")).firstMatch
        if folded.exists { folded.tap(); hold(1) }
        try XCTUnwrap(destination(name, in: app), "No \(name) tab.").tap()
    }

    /// Back from a publication page to the shelf.
    func backToShelf(in app: XCUIApplication) {
        for _ in 0..<3 {
            let back = app.buttons["BackButton"]
            guard back.exists, back.isHittable else { break }
            back.tap()
            hold(1)
        }
    }
}

/// A failure the capture harness prints, where a skip would only be counted.
enum Wave5Failure: Error {
    case because(String)
}
