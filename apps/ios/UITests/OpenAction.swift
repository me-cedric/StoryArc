import XCTest

extension XCTestCase {

    /// The publication page's primary action, once it can be tapped.
    ///
    /// The button exists a beat before the page's push transition ends, and it is not hittable
    /// until it does. Polling until one is hittable turns that race into a wait, and a page that
    /// never offers one into a skip with a picture attached (`no-open-action`).
    @MainActor
    func hittableOpenAction(in app: XCUIApplication, timeout: TimeInterval = 12) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let action = app.buttons.matching(opensAPublication)
                .allElementsBoundByIndex.first(where: \.isHittable) {
                return action
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        shutter(app, named: "no-open-action")
        return nil
    }

    /// Opens one publication by name and says whether a reflowable page arrived.
    ///
    /// A copy of `SweepEpubReaderTests`' own private helper rather than a call to it: that one
    /// is `private` to its file, and the alternative — the shared search — relaunches the app
    /// between attempts and so drops the launch arguments a walk is about.
    @MainActor
    func openReflowableBook(named title: String, in app: XCUIApplication) -> Bool {
        guard (try? showTheShelf(in: app)) != nil else { return false }
        guard let cover = tappableCover(titled: title, in: app) else { return false }
        cover.tap()
        guard let action = hittableOpenAction(in: app) else { return false }
        action.tap()
        let opened = app.webViews.firstMatch.waitForExistence(timeout: 20)
        if !opened {
            // A skip that photographs nothing is a skip nobody can diagnose. This is the
            // frame that says what the reader actually did.
            shutter(app, named: "ios-reflowable-did-not-open")
        }
        return opened
    }

    /// A shelf cover whose **middle** can be tapped.
    ///
    /// `isHittable` answers true for a cover that is half under the floating tab bar, and a
    /// tap at its middle lands on the bar's blur and opens nothing. The walks that took the first
    /// hittable cover then skipped at the publication page, which passes and photographs
    /// nothing (`EpubCurlWalkTests` and `CurlWalkTests` on 2026-10-08). So a cover counts only
    /// when its middle sits between the top bar and the tab bar; one that sits low is brought up
    /// by a short drag, and the alphabetical index is the last resort.
    @MainActor
    func tappableCover(titled title: String, in app: XCUIApplication) -> XCUIElement? {
        let wanted = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title))
        let height = app.windows.firstMatch.frame.height
        func inBand() -> XCUIElement? {
            wanted.allElementsBoundByIndex.first {
                $0.isHittable && $0.frame.midY > 160 && $0.frame.midY < height - 190
            }
        }
        func scroll(by fraction: CGFloat) {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75 - fraction))
            from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        for _ in 0..<10 {
            if let found = inBand() { return found }
            let low = wanted.allElementsBoundByIndex.contains { $0.exists && $0.frame.midY >= height - 190 }
            if low { scroll(by: 0.25) } else { app.swipeUp() }
        }
        if let initial = title.first.map({ String($0).uppercased() }) {
            // The index is one scrubber (24.6): tap it where the initial would sit in A to Z.
            let rail = app.descendants(matching: .any).matching(identifier: "library.rail").firstMatch
            if rail.isHittable, let letter = initial.unicodeScalars.first, ("A"..."Z").contains(letter) {
                let place = (Double(letter.value - 65) + 0.5) / 27
                rail.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: place)).tap()
                for _ in 0..<4 {
                    if let found = inBand() { return found }
                    scroll(by: 0.25)
                }
            }
        }
        return nil
    }
}
