import XCTest

// Two waits for a slow CI runner, where an answer that is only late used to read as a failure.

@MainActor
extension XCTestCase {
    /// Whether `element` is on screen with the same non-empty frame on two reads a quarter of
    /// a second apart: past a fade or a presentation, so `isHittable` and `tap()` can work out
    /// an activation point. `isHittable` on a frame still moving records a failure ("Activation
    /// point invalid") instead of answering false.
    func settled(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let window = app.windows.firstMatch.frame
        let deadline = Date().addingTimeInterval(timeout)
        var last: CGRect?
        while Date() < deadline {
            if element.exists {
                let frame = element.frame
                if !frame.isEmpty, window.contains(CGPoint(x: frame.midX, y: frame.midY)), frame == last {
                    return true
                }
                last = frame
            } else {
                last = nil
            }
            hold(0.25)
        }
        return false
    }
}

@MainActor
extension XCUIApplication {
    /// `performAccessibilityAudit`, run once more when the platform gave up before it finished.
    ///
    /// "Audit failed to complete in time" (code -56) is a timeout, not a finding: it failed
    /// `PlayerAuditTests.testTheSpeedSheetPassesTheAudit` on a CI runner on 2026-10-21 with no
    /// issue reported. Only that error gets the second run; a finding, or any other error, fails
    /// as before. An issue the first, unfinished run already reported can reach the handler twice.
    func auditAllowingOneTimeout(
        for types: XCUIAccessibilityAuditType = .all,
        _ handler: ((XCUIAccessibilityAuditIssue) throws -> Bool)? = nil
    ) throws {
        do {
            try performAccessibilityAudit(for: types, handler)
        } catch let error as NSError
            where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            try performAccessibilityAudit(for: types, handler)
        }
    }
}

@MainActor
extension XCUIElement {
    /// `isHittable` that answers false, not fails, for an element without a usable frame.
    ///
    /// `isHittable` *records a test failure* — "Failed to determine hittability … Activation
    /// point invalid" — when it meets an element whose frame is empty or still moving: a
    /// button mid-fade, a play button turning into pause. Every helper that searched with it
    /// could fail a test that asserts nothing about that element; on 2026-10-21 and 22 it did
    /// in `revealed`, `hittable` and `pauseWhatPlays`. The expected failure covers this one
    /// query and nothing the test asserts afterwards.
    var isReachable: Bool {
        guard exists, !frame.isEmpty else { return false }
        var hit = false
        XCTExpectFailure("The element moved while its hit point was being worked out.", strict: false) {
            hit = isHittable
        }
        return hit
    }
}
