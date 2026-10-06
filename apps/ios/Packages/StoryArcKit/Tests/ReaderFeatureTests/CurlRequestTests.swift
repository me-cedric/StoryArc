import Foundation
import Testing

import StoryArcCore

@testable import ReaderFeature

/// That a tap, a key or a controller turns the page the way Curl turns pages.
///
/// `page-transitions` gives Curl one motion and the finger was the only thing that ran it:
/// an edge tap cut to the next page, so the mode a reader chose for its fold looked like
/// Fast fade to everyone who taps. The rule is here; the wiring that carries it is below,
/// read as source text for the reason `TapZoneWiringTests` sets out — a closure that calls
/// the wrong function cannot be asserted as a value.
///
/// Android's `CurlRequestTest` asserts the same table.
@Suite("A turn nobody dragged still curls")
struct CurlRequestTests {

    // MARK: - The rule

    @Test("A single step in Curl mode runs the curl")
    func singleStepCurls() {
        #expect(CurlRequest.runsCurl(mode: .pageCurl, step: 1, hasDestination: true))
        #expect(CurlRequest.runsCurl(mode: .pageCurl, step: -1, hasDestination: true))
    }

    @Test("Every other mode brings its own motion and is left alone")
    func otherModesCut() {
        for mode in [PageTransition.slide, .fastFade, .verticalScroll, .horizontalScroll] {
            #expect(!CurlRequest.runsCurl(mode: mode, step: 1, hasDestination: true))
        }
    }

    @Test("A jump of several pages has no fold to roll")
    func jumpsCut() {
        #expect(!CurlRequest.runsCurl(mode: .pageCurl, step: 7, hasDestination: true))
        #expect(!CurlRequest.runsCurl(mode: .pageCurl, step: 0, hasDestination: true))
    }

    @Test("A refused turn is refused rather than curled into nothing")
    func refusedTurnDoesNotCurl() {
        // D13: the refusal owes a haptic and a rubber-band, and both live on the far side
        // of `turn(by:)`. A request filed here would swallow them.
        #expect(!CurlRequest.runsCurl(mode: .pageCurl, step: 1, hasDestination: false))
    }

    @Test("Two taps in the same direction are two different requests")
    func serialsDiffer() {
        // Equal values, and `onChange` sees no change between two of them: the second tap
        // turned no page at all until the serial told them apart.
        #expect(CurlRequest(isForward: true, serial: 1) != CurlRequest(isForward: true, serial: 2))
    }

    // MARK: - The wiring

    /// `apps/ios`, found from this file rather than from the working directory, because this
    /// repository nests agent worktrees and a walk upwards leaves the checkout under test.
    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/ReaderFeatureTests/this file → apps/ios
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory
    }()

    private func source(_ relativePath: String) throws -> String {
        let url = Self.appleRoot.appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    @Test("A tap zone and a reading-order turn both ask the transition for the turn")
    func tapsAndKeysAskTheTransition() throws {
        let turning = try source("Packages/StoryArcKit/Sources/ReaderFeature/ReaderTurning.swift")

        #expect(
            turning.contains("turnWithTransition(by: -1)") && turning.contains("turnWithTransition(by: 1)"),
            "An edge tap calls turn(by:) again, which cuts to the next page in Curl mode."
        )
        #expect(
            turning.contains("turnWithTransition(by: readingOrderStep(step, isRightToLeft: isRightToLeft))"),
            """
            turnInReadingOrder no longer routes through the transition, so Space, Page Up
            and Page Down cut while an edge tap curls.
            """
        )
    }

    @Test("The arrow keys and the controller ask for it too")
    func keysAndControllerAskTheTransition() throws {
        let view = try source("Packages/StoryArcKit/Sources/ReaderFeature/ReaderView.swift")

        #expect(
            view.contains(".onKeyPress(.leftArrow) { turnWithTransition(by: -1)"),
            "The arrow keys cut again."
        )
        #expect(
            view.contains("GameControllerTurning(onTurn: turnWithTransition)"),
            "A controller's d-pad cuts again."
        )
    }

    @Test("The curl's own completion commits the page instead of asking for another turn")
    func completionDoesNotAskAgain() throws {
        let containers = try source("Packages/StoryArcKit/Sources/ReaderFeature/ReaderContainers.swift")

        #expect(
            !containers.contains("onTurned: { turnInReadingOrder"),
            """
            CurledPages' onTurned routes through the transition again. It is called after the
            curl has already rolled the page over, so a request filed there rolls it over
            again, and again. `CurlOverImagePagesTests` owns the positive claim that the step
            it takes instead is still a reading-order one.
            """
        )
    }
}
