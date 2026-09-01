import Foundation
import Testing

@testable import Playback

/// Stopping a book for a listener who is falling asleep.
///
/// `audio-playback`, *Sleep timer*:
///
/// > **THEN** a duration or *end of chapter* may be chosen, the remaining time is shown on
/// > the player, and playback fades out rather than cutting off when it elapses
/// > **AND** the position at which it stopped is recorded, so resuming starts a little
/// > before it rather than where the fade ended
///
/// All of it is here except the ticking, the fade reaching the engine and the recording,
/// which are ``PlayerCentre``'s — `SleepTimerRunningTests`.
///
/// **The mirror of Android's `SleepTimerTest`, case for case**, because the two platforms'
/// sleep timers are one product decision and a divergence here would be a listener falling
/// asleep in different places on the two. The one thing that is deliberately not mirrored is
/// the unit: Android counts milliseconds because media3 does, and this counts seconds
/// because `AVPlayer` does.
@Suite("The sleep timer")
struct SleepTimerTests {

    /// A narrated part ten minutes long, with the audio wherever the case needs it.
    private func playing(at offset: TimeInterval = 0, of total: TimeInterval? = 600) -> PlaybackTime {
        PlaybackTime(elapsed: offset, total: total)
    }

    // MARK: - A duration

    @Test("A chosen duration starts counting from itself")
    func durationStartsFromItself() throws {
        let timer = try #require(SleepCountdown.of(.after(15 * 60), playing: playing()))

        #expect(timer.remaining == 900)
    }

    @Test("Time passing takes it down")
    func timePassingTakesItDown() {
        let timer = SleepCountdown(timer: .after(900), remaining: 900)

        #expect(timer.ticked(by: 1, playing: playing()).remaining == 899)
    }

    @Test("It stops at nothing left rather than going negative")
    func itStopsAtNothingLeft() {
        let elapsed = SleepCountdown(timer: .after(900), remaining: 0.5).ticked(by: 1, playing: playing())

        #expect(elapsed.remaining == 0)
        #expect(elapsed.hasElapsed)
    }

    @Test("A duration of nothing is not a timer")
    func nothingIsNotATimer() {
        #expect(SleepCountdown.of(.after(0), playing: playing()) == nil)
    }

    // MARK: - End of chapter

    @Test("End of chapter is what is left of the part being played")
    func endOfChapterIsWhatIsLeft() throws {
        let timer = try #require(SleepCountdown.of(.endOfChapter, playing: playing(at: 120)))

        #expect(timer.remaining == 480)
    }

    /// A listener who skips forward has moved the end nearer.
    ///
    /// Re-read rather than counted down, because a timer keeping its own count would stop
    /// them somewhere in the *next* chapter — which is the one thing choosing end of chapter
    /// asks not to happen.
    @Test("Skipping forward inside the chapter brings the end nearer")
    func skippingForwardBringsTheEndNearer() {
        let timer = SleepCountdown(timer: .endOfChapter, remaining: 480)

        #expect(timer.ticked(by: 1, playing: playing(at: 500)).remaining == 100)
    }

    /// And skipping back pushes it away again, which is the same rule read the other way.
    @Test("Skipping back inside the chapter pushes the end away")
    func skippingBackPushesTheEndAway() {
        let timer = SleepCountdown(timer: .endOfChapter, remaining: 100)

        #expect(timer.ticked(by: 1, playing: playing(at: 60)).remaining == 540)
    }

    /// `audio-playback`: "every control the player offers works, or is absent — none is
    /// present and refusing".
    ///
    /// A publication being read aloud has no true duration, so there is no end of chapter to
    /// stop at, and the option is absent rather than doing nothing. Android's `SleepTimer.of`
    /// answers null in exactly the same case, and its chip is not drawn.
    @Test("End of chapter is not offered where nothing knows how long the chapter is")
    func endOfChapterNeedsALength() {
        #expect(SleepCountdown.of(.endOfChapter, playing: playing(of: nil)) == nil)
    }

    @Test("A duration is still offered where nothing knows how long the chapter is")
    func aDurationSurvivesAnUnknownLength() {
        #expect(SleepCountdown.of(.after(900), playing: playing(of: nil)) != nil)
    }

    /// An end-of-chapter timer whose part loses its length keeps the count it had rather
    /// than resetting or elapsing — the source that reported no duration is not the source
    /// that said the listener has arrived.
    @Test("An end-of-chapter timer holds its count where a length disappears")
    func endOfChapterHoldsWithoutALength() {
        let timer = SleepCountdown(timer: .endOfChapter, remaining: 300)

        #expect(timer.ticked(by: 1, playing: playing(of: nil)).remaining == 300)
    }

    // MARK: - The fade

    @Test("The audio is at full volume until the fade begins")
    func fullVolumeUntilTheFade() {
        #expect(SleepCountdown(timer: .after(900), remaining: 900).gain == 1)
        #expect(SleepCountdown(timer: .after(900), remaining: SleepCountdown.fade).gain == 1)
    }

    /// A straight ramp, which is the shape `design.md` records: "a listener who is nearly
    /// asleep should not be woken by silence arriving all at once".
    @Test("It fades on a straight ramp rather than cutting off")
    func itFadesRatherThanCutting() {
        let half = SleepCountdown(timer: .after(900), remaining: SleepCountdown.fade / 2)
        let quarter = SleepCountdown(timer: .after(900), remaining: SleepCountdown.fade / 4)

        #expect(abs(half.gain - 0.5) < 0.01)
        #expect(abs(quarter.gain - 0.25) < 0.01)
        #expect(half.gain != 0, "half way through the fade is not silence")
    }

    @Test("It is silent when it has elapsed")
    func silentOnceElapsed() {
        #expect(SleepCountdown(timer: .after(900), remaining: 0).gain == 0)
    }

    // MARK: - The two product decisions

    /// **One number for the fade and the rewind**, and that is the argument for it: the fade
    /// is exactly the stretch a listener stopped taking in, so starting again where it
    /// *began* is starting at the last thing they properly heard. Android holds the same
    /// number under one constant; this asserts the two have not drifted apart.
    @Test("The rewind is the fade's own length")
    func theRewindIsTheFade() {
        #expect(SleepCountdown.rewind == SleepCountdown.fade)
        #expect(SleepCountdown.fade == 30)
    }

    @Test("The place recorded is one rewind before where the fade ended")
    func recordedPlaceIsOneRewindBack() {
        let place = SleepCountdown.recordedPlace(afterFadingAt: PlaybackPlace(partIndex: 2, offset: 100))

        #expect(place == PlaybackPlace(partIndex: 2, offset: 100 - SleepCountdown.rewind))
    }

    /// Never before the start of the part it is in. A listener who fell asleep in the first
    /// half-minute of a chapter starts it again, not the one before it.
    @Test("It never lands before the start of the part")
    func recordedPlaceClampsAtZero() {
        let place = SleepCountdown.recordedPlace(afterFadingAt: PlaybackPlace(partIndex: 1, offset: 4))

        #expect(place == PlaybackPlace(partIndex: 1, offset: 0))
    }

    /// **The five durations are a product decision**, recorded as one in `design.md`, and
    /// they are Android's `OFFERED_MINUTES` to the minute. A platform offering a sixth would
    /// be a platform where the same listener has a different set of choices.
    @Test("The durations offered are the five Android offers")
    func theDurationsMatchAndroid() {
        #expect(SleepTimer.durations == [5, 15, 30, 45, 60].map { TimeInterval($0) * 60 })
    }
}
