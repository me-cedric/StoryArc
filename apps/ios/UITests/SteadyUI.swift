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
            if let frame = element.currentFrame {
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
    /// `performAccessibilityAudit`, run again one check at a time when the platform gave up.
    ///
    /// "Audit failed to complete in time" (code -56) is a timeout, not a finding. On CI runners
    /// it hit the whole-screen audit of the theme sheet and the library notice twice in a row
    /// (run 39745852241, 2026-10-22), so a plain second run is not enough: the fallback runs each
    /// audit type of `types` on its own, the same checks in pieces small enough to finish. Only
    /// that error gets the fallback; a finding, or any other error, fails as before. An issue the
    /// unfinished run already reported can reach the handler twice.
    func auditSplittingOnTimeout(
        for types: XCUIAccessibilityAuditType = .all,
        _ handler: ((XCUIAccessibilityAuditIssue) throws -> Bool)? = nil
    ) throws {
        do {
            try performAccessibilityAudit(for: types, handler)
        } catch let error as NSError
            where error.domain == "com.apple.xcode.xctest.accessibilityAudit" && error.code == -56 {
            let single: [XCUIAccessibilityAuditType] = [
                .contrast, .elementDetection, .hitRegion, .sufficientElementDescription,
                .dynamicType, .textClipped, .trait,
            ]
            for type in single where types.contains(type) {
                try performAccessibilityAudit(for: type, handler)
            }
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
        var hit = false
        // `exists` and `frame` too: an element that went between two reads fails the test with
        // "Failed to get matching snapshot" (CI run 39745914279, 2026-10-22).
        XCTExpectFailure("The element moved while its hit point was being worked out.", strict: false) {
            hit = exists && !frame.isEmpty && isHittable
        }
        return hit
    }

    /// `frame`, or nil when the element has gone, without failing the test.
    var currentFrame: CGRect? {
        var found: CGRect?
        XCTExpectFailure("The element went while its frame was being read.", strict: false) {
            if exists { found = frame }
        }
        return found
    }
}
