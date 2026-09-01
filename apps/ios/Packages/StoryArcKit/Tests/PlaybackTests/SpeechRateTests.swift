import AVFoundation
import Foundation
import Testing

@testable import Playback

/// The player's speed, in the units `AVSpeechUtterance` takes.
///
/// **The mapping is ours, and it has to be, so it is asserted here.** Readium 3.11.0 has a
/// `rateMultiplierToAVRate` and it is `private` — the only public way to set a rate on a
/// synthesised utterance is `AVTTSEngineDelegate`, which hands over an `AVSpeechUtterance`
/// and lets the caller write `rate` itself. So this project owns the conversion, and the
/// three anchors below are the whole of what it promises.
///
/// **Why not a straight line.** The obvious mapping is one lerp from 0.5…3 onto
/// `AVSpeechUtteranceMinimumSpeechRate`…`AVSpeechUtteranceMaximumSpeechRate`. Measured on
/// 2026-09-01 those constants are `0.0`, `0.5` and `1.0` — evenly spaced as numbers, which
/// is exactly what makes the naive lerp look right and be wrong: it puts 1× at
/// `(1 - 0.5) / (3 - 0.5) = 0.2`, well below the platform's own default of `0.5`. A listener
/// who never touched the speed control would get a voice noticeably slower than the one the
/// system reads everything else at, and nothing in a build would say so.
///
/// So the mapping is two lines meeting at the default, and `normalIsThePlatformDefault`
/// below is the assertion that fails if anyone straightens it.
@Suite("Speech rate")
struct SpeechRateTests {

    private let min = Double(AVSpeechUtteranceMinimumSpeechRate)
    private let normal = Double(AVSpeechUtteranceDefaultSpeechRate)
    private let max = Double(AVSpeechUtteranceMaximumSpeechRate)

    @Test("Half speed is the slowest rate the platform has")
    func slowestIsTheSlowest() {
        #expect(Double(SpeechRate.avRate(for: .slowest)) == min)
    }

    @Test("Triple speed is the fastest rate the platform has")
    func fastestIsTheFastest() {
        #expect(Double(SpeechRate.avRate(for: .fastest)) == max)
    }

    /// The one a naive lerp gets wrong. See the suite's own note.
    @Test("Normal speed is the platform's own default, not the middle of the range")
    func normalIsThePlatformDefault() {
        #expect(Double(SpeechRate.avRate(for: .normal)) == normal)
        let naive = min + (1 - PlaybackSpeed.slowestRate)
            / (PlaybackSpeed.fastestRate - PlaybackSpeed.slowestRate) * (max - min)
        #expect(Double(SpeechRate.avRate(for: .normal)) != naive)
    }

    @Test("Faster is always faster, across every stop the picker offers")
    func monotonic() {
        let rates = PlaybackSpeed.stops.map { SpeechRate.avRate(for: $0) }
        #expect(rates == rates.sorted())
        #expect(Set(rates).count == rates.count)
    }

    @Test("A speed between two anchors lands between their rates")
    func betweenAnchors() {
        let slow = Double(SpeechRate.avRate(for: PlaybackSpeed(0.75)))
        #expect(slow > min && slow < normal)
        let fast = Double(SpeechRate.avRate(for: PlaybackSpeed(2)))
        #expect(fast > normal && fast < max)
    }

    /// `PlaybackSpeed` clamps on the way in, so nothing can ask for a rate the platform
    /// would pin silently — the utterance would speak at a speed the player did not state.
    @Test("A speed outside the range cannot produce a rate outside the platform's")
    func clamped() {
        #expect(Double(SpeechRate.avRate(for: PlaybackSpeed(-4))) == min)
        #expect(Double(SpeechRate.avRate(for: PlaybackSpeed(99))) == max)
    }
}
