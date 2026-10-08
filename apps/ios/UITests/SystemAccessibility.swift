import XCTest

extension XCTestCase {

    /// Turns one switch on *Settings › Accessibility › Display & Text Size* on or off, by driving
    /// the Settings app.
    ///
    /// `simctl ui` has a switch for Increase Contrast and none for Reduce Transparency, so the
    /// refusal frames of `reader-theming-and-page-transitions` 0.5 and 7.6 need the real
    /// control. The walk is tolerant of where Settings opens, because it restores the last pane
    /// it showed: it taps whichever of the three rows it can see, and goes back when it sees none.
    @MainActor
    func setDisplaySwitch(_ name: String, on: Bool) throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        defer { settings.terminate() }

        let wanted = settings.switches[name]
        for _ in 0..<8 where !wanted.exists {
            let display = settings.staticTexts["Display & Text Size"].firstMatch
            let accessibility = settings.staticTexts["Accessibility"].firstMatch
            if display.exists && display.isHittable {
                display.tap()
            } else if accessibility.exists && accessibility.isHittable {
                accessibility.tap()
            } else if settings.navigationBars.buttons.firstMatch.isHittable {
                settings.navigationBars.buttons.firstMatch.tap()
            }
            _ = wanted.waitForExistence(timeout: 2)
        }
        try XCTSkipUnless(wanted.exists, "Settings offered no “\(name)” switch.")
        if (wanted.value as? String == "1") != on {
            // The row is wide and its switch sits at the trailing end; a tap at the middle of
            // the row lands on the label.
            wanted.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        let took = NSPredicate(format: "value == %@", on ? "1" : "0")
        let result = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: took, object: wanted)],
            timeout: 5
        )
        XCTAssertEqual(result, .completed, "“\(name)” did not take; it reads \(String(describing: wanted.value)).")
    }
}
