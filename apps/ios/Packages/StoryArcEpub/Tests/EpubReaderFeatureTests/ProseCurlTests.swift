import CoreGraphics
import Testing
import UIKit

import StoryArcCore
@testable import EpubReaderFeature

/// The finger drives the curl over prose, with the comic reader's release rule. Task 8.12,
/// owner answer O1. Android's `ProseCurlTest` asserts the same table.
@MainActor
@Suite("The finger-driven curl over prose")
struct ProseCurlTests {

    private let forward = ProseCurl(isForward: true, isRightToLeft: false)
    private let backward = ProseCurl(isForward: false, isRightToLeft: false)

    @Test("The first sideways travel picks the turn, and right-to-left mirrors it")
    func theFirstTravelPicksTheTurn() {
        #expect(ProseCurl.starting(travel: -12, isRightToLeft: false) == forward)
        #expect(ProseCurl.starting(travel: 12, isRightToLeft: false) == backward)
        #expect(ProseCurl.starting(travel: 12, isRightToLeft: true)?.isForward == true)
        #expect(ProseCurl.starting(travel: 0, isRightToLeft: false) == nil)
    }

    @Test("The page follows the finger, in the turn's own direction only")
    func thePageFollowsTheFinger() {
        #expect(abs(forward.progress(base: 0, travel: -300, width: 1000) - 0.3) < 0.001)
        // Back past where it started: the navigator moved forward, so the page lies flat.
        #expect(forward.progress(base: 0, travel: 300, width: 1000) == 0)
        #expect(abs(backward.progress(base: 0, travel: 300, width: 1000) + 0.3) < 0.001)
        #expect(backward.progress(base: 0, travel: -300, width: 1000) == 0)
        // A drag that caught a settle at 0.8 counts from 0.8.
        #expect(abs(forward.progress(base: 0.8, travel: 100, width: 1000) - 0.7) < 0.001)
    }

    @Test("Released past halfway the turn completes, before it the page springs back")
    func theReleaseRuleIsTheComicReaders() {
        #expect(forward.target(reached: 0.6, velocity: 0) == 1)
        #expect(forward.target(reached: 0.4, velocity: 0) == 0)
        #expect(backward.target(reached: -0.6, velocity: 0) == -1)
        #expect(backward.target(reached: -0.4, velocity: 0) == 0)
    }

    @Test("A flick completes a short turn, and a flick the other way springs it back")
    func aFlickCompletes() {
        // 2000 points a second leftwards predicts 100 points of travel, past the 40 a flick needs.
        #expect(forward.target(reached: 0.1, velocity: -2000) == 1)
        #expect(forward.target(reached: 0.1, velocity: 2000) == 0)
        #expect(backward.target(reached: -0.1, velocity: 2000) == -1)
        // A page that never left flat is not a turn, however fast the finger left it.
        #expect(forward.target(reached: 0.01, velocity: -2000) == 0)
    }

    @Test("A tap or a key springs to a whole turn in its own direction")
    func aTapSpringsToAWholeTurn() {
        #expect(forward.whole == 1)
        #expect(backward.whole == -1)
    }

    @Test("The sheet turns the leaving page forward, and rolls the arriving page in going back")
    func theSheetsAreTheComicReaders() throws {
        let leaving = try Self.image(), arriving = try Self.image()

        let ahead = ReflowableCurl.sheets(progress: 0.3, page: leaving, other: arriving)
        #expect(ahead.turning === leaving && ahead.under === arriving && ahead.progress == 0.3)

        let back = ReflowableCurl.sheets(progress: -0.3, page: leaving, other: arriving)
        #expect(back.turning === arriving && back.under === leaving && abs(back.progress - 0.7) < 0.001)
    }

    @Test("With no arriving page yet, the leaving page lies flat whatever the finger did")
    func noArrivingPageLiesFlat() throws {
        let leaving = try Self.image()

        let sheets = ReflowableCurl.sheets(progress: 0.4, page: leaving, other: nil)

        #expect(sheets.turning === leaving)
        #expect(sheets.progress == 0)
    }

    @Test("A pan that is cancelled lets go of the page like a finger that lifted")
    func aCancelledPanLetsGo() {
        #expect(TurnGestures.phase(of: .began, travel: -10, velocity: 0) == .began(travel: -10))
        #expect(TurnGestures.phase(of: .changed, travel: -50, velocity: 0) == .changed(travel: -50))
        #expect(TurnGestures.phase(of: .ended, travel: -50, velocity: -9) == .ended(travel: -50, velocity: -9))
        #expect(TurnGestures.phase(of: .cancelled, travel: -50, velocity: 0) == .ended(travel: -50, velocity: 0))
        #expect(TurnGestures.phase(of: .possible, travel: 0, velocity: 0) == nil)
    }

    @Test("A turn leaves the resource only past its first or its last page")
    func aTurnLeavesTheResourceAtItsEdges() {
        // Three pages of 400 points: offsets 0, 400 and 800.
        #expect(!ProsePages.crossesResource(offset: 0, width: 400, contentWidth: 1200, step: 1))
        #expect(!ProsePages.crossesResource(offset: 400, width: 400, contentWidth: 1200, step: 1))
        #expect(ProsePages.crossesResource(offset: 800, width: 400, contentWidth: 1200, step: 1))
        #expect(ProsePages.crossesResource(offset: 0, width: 400, contentWidth: 1200, step: -1))
        #expect(!ProsePages.crossesResource(offset: 400, width: 400, contentWidth: 1200, step: -1))
        // A web view not laid out yet cannot be asked, and is treated as the edge.
        #expect(ProsePages.crossesResource(offset: 0, width: 0, contentWidth: 0, step: 1))
    }

    @Test("A forward turn moves right in a left-to-right book and left in a right-to-left one")
    func theStepMirrors() {
        #expect(ProsePages.step(forward: true, isRightToLeft: false) == 1)
        #expect(ProsePages.step(forward: false, isRightToLeft: false) == -1)
        #expect(ProsePages.step(forward: true, isRightToLeft: true) == -1)
        #expect(ProsePages.step(forward: false, isRightToLeft: true) == 1)
    }

    static func image() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }
}
