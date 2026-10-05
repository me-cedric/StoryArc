import Foundation
import Testing

@testable import ReaderFeature
@testable import StoryArcCore

/// That a device judges its own curl, and that a slow one withholds it without losing the
/// reader's choice.
///
/// `page-transitions`: Curl is absent where the device "cannot render it at the display's
/// refresh rate", and "a user who set Curl on a capable device and later opens the library on
/// this one reads with Slide without their stored preference being overwritten". Until D11
/// nothing measured the first half, so no device had ever withheld Curl for the refresh rate.
///
/// **No case below states a frame rate.** A strain is a ratio of what a turn cost to what the
/// panel allowed for it, so every number here is dimensionless and none can be misread as a
/// claim about a phone. Android's `CurlCapabilityTest` asserts the same table.
@Suite("A device judges its own curl")
struct CurlCapabilityTests {

    /// A store nobody else writes, so a case cannot see another case's device.
    private func store() throws -> CurlCapability {
        CurlCapability(defaults: try #require(UserDefaults(suiteName: "curl-\(UUID().uuidString)")))
    }

    @Test("A device is given the curl until it has failed, not until it has passed")
    func unjudgedDevicesCurl() throws {
        let capability = try store()
        #expect(capability.isUnjudged)
        #expect(!capability.cannotCurl)

        // Two bad turns are not an answer either: the third is what decides, and a reader
        // who has curled twice on a new phone is still curling.
        capability.record(strain: 3)
        capability.record(strain: 3)
        #expect(capability.isUnjudged)
        #expect(!capability.cannotCurl)
    }

    @Test("Three turns that miss a third of their frames withhold the curl")
    func aSlowDeviceIsJudged() throws {
        let capability = try store()
        for _ in 0..<CurlVerdict.turns { capability.record(strain: 2) }
        #expect(!capability.isUnjudged)
        #expect(capability.cannotCurl)
    }

    @Test("Three turns that keep up leave the curl alone, for good")
    func aFastDeviceKeepsIt() throws {
        let capability = try store()
        for _ in 0..<CurlVerdict.turns { capability.record(strain: 1) }
        #expect(!capability.isUnjudged)
        #expect(!capability.cannotCurl)
        // And the instrument stops: a judged device pays for no more frame clocks.
        capability.record(strain: 9)
        #expect(!capability.cannotCurl)
    }

    @Test("One cold first turn does not condemn a device that draws the rest perfectly")
    func theMedianSurvivesOneBadTurn() throws {
        // The reason for a median rather than a mean. A first curl that costs three times its
        // budget, then two that cost nothing extra: the mean is 1.67 and fails, the median is
        // 1 and passes.
        let capability = try store()
        for strain in [3.0, 1.0, 1.0] { capability.record(strain: strain) }
        #expect(!capability.cannotCurl)
    }

    @Test("A turn of one frame says nothing, so it is not counted")
    func oneFrameIsNotAMeasurement() {
        var run = FrameRun(isEnabled: true)
        run.begin()
        run.record(at: 0, expecting: 0.01)
        #expect(run.strain == nil)
    }

    @Test("The strain is what the turn cost over what the panel allowed for it")
    func strainIsARatio() {
        // Ten frames handed over with one missed between each pair: the app drew nine
        // intervals' worth of page in eighteen intervals of time.
        var run = FrameRun(isEnabled: true)
        run.begin()
        for step in 0..<10 { run.record(at: Double(step) * 0.02, expecting: 0.01) }
        #expect(run.dropped == 9)
        #expect(abs((run.strain ?? 0) - 2) < 0.001)

        // And a turn that dropped nothing is exactly 1, whatever its length.
        var kept = FrameRun(isEnabled: true)
        kept.begin()
        for step in 0..<10 { kept.record(at: Double(step) * 0.01, expecting: 0.01) }
        #expect(kept.strain == 1)
    }

    @Test("A device that cannot curl keeps the reader's stored Curl")
    func theStoredChoiceSurvives() {
        // The half of the scenario that is about the reader rather than the device. The
        // verdict reaches `TransitionChoices` as `canCurl`, and nothing writes `chosen`.
        let choices = TransitionChoices(
            chosen: .pageCurl, axis: .vertical, reduceMotion: false, canCurl: false
        )
        #expect(choices.chosen == .pageCurl)
        #expect(choices.effective == .slide)
        #expect(choices.curlIsAbsent)
    }
}
