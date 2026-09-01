import Foundation
import Testing

@testable import Playback

/// The sleep timer as a listener meets it: counting down, fading, and stopping the book.
///
/// **These are the tests the shipped control never had, and it is why it never worked.**
/// `setSleepTimer` stored a countdown, `sleepTimerElapsed` knew what to do with one, and
/// nothing in the app connected the two — so a listener set *Sleep in 30 minutes*, the
/// remaining time never changed, and the audio never stopped. `audio-playback` forbids that
/// by name: "every control the player offers works, or is absent — none is present and
/// refusing."
///
/// The clock is the platform's — see ``PlaybackPlatform/sleepTimerChanged(isRunning:)`` for
/// why — so every case here moves time by calling ``PlayerCentre/tickSleepTimer(by:)``
/// itself. A thirty-second fade waited out in real time is thirty seconds of a unit test.
@MainActor
@Suite("The sleep timer, running")
struct SleepTimerRunningTests {

    /// A session on a narrated book, playing, with the timer's own recorder wired.
    private func session(_ kind: SourceKind = .narrated) -> (PlayerCentre, PlaybackSourceDouble) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Sea Room", format: .audiobook), source: source)
        return (centre, source)
    }

    // MARK: - It moves

    /// The defect, stated as a test. The remaining time has to *change*, because
    /// `audio-playback` asks for it to be "shown on the player" and a number that never
    /// moves is the same defect in a different costume.
    @Test("A duration counts down as time passes")
    func aDurationCountsDown() throws {
        let (centre, _) = session()
        centre.setSleepTimer(.after(600))

        #expect(centre.sleep?.remaining == 600)
        centre.tickSleepTimer(by: 0.5)
        #expect(centre.sleep?.remaining == 599.5)
        centre.tickSleepTimer(by: 0.5)
        #expect(centre.sleep?.remaining == 599)
    }

    /// End of chapter is re-read from where the audio has reached rather than counted down,
    /// so a listener who skips forward inside the chapter has moved the end nearer.
    @Test("A skip forward inside the chapter moves the end nearer")
    func aSkipForwardMovesTheEndNearer() {
        let (centre, source) = session()
        source.advance(toPart: 0, offset: 30)
        centre.setSleepTimer(.endOfChapter)
        #expect(centre.sleep?.remaining == 90, "ninety seconds left of a two-minute chapter")

        source.advance(toPart: 0, offset: 100)

        #expect(centre.sleep?.remaining == 20, "the end of the chapter is twenty seconds away now")
    }

    // MARK: - It holds while paused

    /// A paused book is not falling asleep. The count holds where it is, which is what a
    /// listener who paused to answer the door means by it.
    @Test("The count holds while the book is paused")
    func theCountHoldsWhilePaused() {
        let (centre, _) = session()
        centre.setSleepTimer(.after(600))
        centre.toggle()

        centre.tickSleepTimer(by: 0.5)
        centre.tickSleepTimer(by: 0.5)

        #expect(centre.sleep?.remaining == 600)
        #expect(!centre.isPlaying)
    }

    @Test("And carries on from where it held once playing resumes")
    func theCountResumes() {
        let (centre, _) = session()
        centre.setSleepTimer(.after(600))
        centre.toggle()
        centre.tickSleepTimer(by: 0.5)

        centre.toggle()
        centre.tickSleepTimer(by: 0.5)

        #expect(centre.sleep?.remaining == 599.5)
    }

    // MARK: - The fade reaches the engine

    /// `audio-playback`: playback "fades out rather than cutting off when it elapses". The
    /// shape is `SleepTimerTests`'; this is the half that proves the number reaches the
    /// thing that makes the sound.
    @Test("The fade reaches the source's own volume")
    func theFadeReachesTheSource() {
        let (centre, source) = session()
        centre.setSleepTimer(.after(SleepCountdown.fade))

        centre.tickSleepTimer(by: SleepCountdown.fade / 2)

        let faded = source.calls.compactMap { call -> Double? in
            if case let .volume(gain) = call { return gain } else { return nil }
        }
        #expect(faded.contains { abs($0 - 0.5) < 0.01 }, "half way through the fade, half the volume")
    }

    /// Replacing or clearing a timer part way through its fade puts the volume back, or a
    /// listener who changed their mind would be left with a book they can barely hear.
    @Test("Clearing a timer part way through the fade restores the volume")
    func clearingRestoresTheVolume() {
        let (centre, source) = session()
        centre.setSleepTimer(.after(SleepCountdown.fade))
        centre.tickSleepTimer(by: SleepCountdown.fade / 2)

        centre.setSleepTimer(nil)

        #expect(centre.sleep == nil)
        #expect(source.calls.last == .volume(1))
    }

    // MARK: - It elapses

    /// The whole point of the mechanism: the audio stops.
    @Test("Running out stops the book")
    func runningOutStopsTheBook() {
        let (centre, source) = session()
        centre.setSleepTimer(.after(1))

        centre.tickSleepTimer(by: 1)

        #expect(centre.sleep == nil, "the timer is spent, not still counting")
        #expect(!centre.isPlaying, "the book stopped")
        #expect(centre.isRunning, "and the session is still there to be resumed")
        #expect(source.calls.contains(.pause))
    }

    /// `audio-playback`: "the position at which it stopped is recorded, so resuming starts a
    /// little before it rather than where the fade ended".
    ///
    /// Recorded by the centre when the timer elapses rather than left to the next tick,
    /// because the next tick only happens while something is playing and nothing is.
    @Test("The position recorded is one rewind before where the fade ended")
    func theRecordedPositionIsRewound() throws {
        let (centre, source) = session()
        let recorder = Recorder()
        centre.onRecord = { recorder.append($0) }
        source.advance(toPart: 1, offset: 60)
        centre.setSleepTimer(.after(1))

        centre.tickSleepTimer(by: 1)

        #expect(
            try #require(recorder.last).position
                == .listening(part: 1, partCount: 3, offset: 60 - SleepCountdown.rewind, of: 90)
        )
    }

    /// And the live session goes back there too, so pressing play does not start mid-word in
    /// a stretch the listener already slept through.
    @Test("The audio itself is moved back where it has a clock to move on")
    func theAudioIsMovedBack() {
        let (centre, source) = session()
        source.advance(toPart: 1, offset: 60)
        centre.setSleepTimer(.after(1))

        centre.tickSleepTimer(by: 1)

        #expect(source.calls.contains(.seek(part: 1, offset: 60 - SleepCountdown.rewind)))
    }

    /// A synthesised voice has no seconds to move through — ``PlaybackSource/seek(toPart:offset:)``
    /// is documented as never being asked of one — so for that source the record is the whole
    /// of the rewind and no seek is attempted.
    @Test("A voice with no clock is not asked to seek")
    func aVoiceIsNotAskedToSeek() {
        let (centre, source) = session(.spoken)
        centre.setSleepTimer(.after(1))

        centre.tickSleepTimer(by: 1)

        #expect(!centre.isPlaying)
        #expect(!source.calls.contains { if case .seek = $0 { true } else { false } })
    }

    // MARK: - Setting, replacing, clearing

    @Test("Replacing a running timer starts the new one from itself")
    func replacingStartsAgain() {
        let (centre, _) = session()
        centre.setSleepTimer(.after(600))
        centre.tickSleepTimer(by: 60)

        centre.setSleepTimer(.after(300))

        #expect(centre.sleep?.remaining == 300)
        #expect(centre.sleep?.timer == .after(300))
    }

    @Test("Clearing one leaves no timer at all")
    func clearingLeavesNone() {
        let (centre, _) = session()
        centre.setSleepTimer(.after(600))

        centre.setSleepTimer(nil)

        #expect(centre.sleep == nil)
        centre.tickSleepTimer(by: 600)
        #expect(centre.isPlaying, "nothing left to stop the book")
    }

    /// `audio-playback`: "every control the player offers works, or is absent". Where nothing
    /// knows how long the chapter is there is no end of chapter to stop at, so the surface
    /// asks this rather than drawing a row that would do nothing — which is what Android's
    /// null from `SleepTimer.of` says to its chip.
    @Test("End of chapter is unavailable where the chapter has no known length")
    func endOfChapterIsUnavailableForAVoice() {
        let (voice, _) = session(.spoken)
        #expect(!voice.canSleepAtEndOfChapter)
        voice.setSleepTimer(.endOfChapter)
        #expect(voice.sleep == nil, "absent, not inert")

        let (narrated, _) = session()
        #expect(narrated.canSleepAtEndOfChapter)
    }

    @Test("Ending the session takes the timer with it")
    func endingClearsIt() {
        let (centre, _) = session()
        centre.setSleepTimer(.after(600))

        centre.end()

        #expect(centre.sleep == nil)
    }

    // MARK: - The platform's clock is started and stopped

    /// The countdown needs a wall clock that keeps running with the screen off, and that is
    /// the platform's. This asserts the centre asks for one and gives it back — a clock left
    /// running after the timer is spent is a phone woken twice a second for nothing.
    @Test("Setting a timer starts the platform's clock, and losing one stops it")
    func theClockIsStartedAndStopped() {
        let centre = PlayerCentre()
        let platform = PlatformDouble()
        centre.platform = platform
        centre.begin(.stub(id: "a", title: "Sea Room", format: .audiobook), source: PlaybackSourceDouble(.narrated))

        centre.setSleepTimer(.after(1))
        #expect(platform.sleepClockRunning == true)

        centre.tickSleepTimer(by: 1)
        #expect(platform.sleepClockRunning == false, "the timer is spent")
    }

    /// Somewhere to put what a session wrote, since `onRecord` is a closure and a local
    /// `var` captured by one cannot be read back under strict concurrency.
    @MainActor
    final class Recorder {
        private(set) var reached: [ReachedListening] = []
        func append(_ one: ReachedListening) { reached.append(one) }
        var last: ReachedListening? { reached.last }
    }
}
