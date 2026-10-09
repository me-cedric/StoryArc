import XCTest

/// `publication-detail` 1.4: the page's cover-tinted wash under Reduce Transparency, beside
/// the same page with the setting off. `DetailBackground.swift` must draw a plain ground.
///
/// `simctl ui` has no switch for it, so `setDisplaySwitch` drives the Settings app, and the
/// teardown puts the switch back.
@MainActor
final class SweepWave5TransparencyTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testCapturePageWashStandard() throws { try walk(reduced: false) }

    func testCapturePageWashReduced() throws { try walk(reduced: true) }

    private func walk(reduced: Bool) throws {
        if reduced {
            try setDisplaySwitch("Reduce Transparency", on: true)
            addTeardownBlock { @MainActor in try? self.setDisplaySwitch("Reduce Transparency", on: false) }
        }
        let app = sweepLaunch(grouping: "issues")
        try w5OpenPage(of: "Tidal Reach #1", in: app)
        hold(2)
        shutter(app, named: "page-wash-\(reduced ? "reduced" : "standard")")
    }
}
