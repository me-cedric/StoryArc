import Foundation
import Testing

@testable import Playback
import StoryArcCore

/// Somewhere for a closure to put what it was handed.
///
/// A local `var` captured by an `@escaping @MainActor` closure cannot be read back under
/// strict concurrency, and a reference the main actor owns can.
@MainActor
final class Positions {
    private(set) var all: [ReadingPosition] = []
    func append(_ one: ReadingPosition) { all.append(one) }
    var last: ReadingPosition? { all.last }
}

/// What the platform taking the audio does to a running session.
///
/// The transitions themselves are `PlaybackTransitionTests`'. These assert the layer above:
/// that ``PlayerCentre`` acts on them — pausing the engine, resuming it, writing the
/// position — and that it does the same thing whichever source is behind it. The
/// notification that triggers each is `PlaybackAudioSession`'s and cannot be raised from a
/// host test; everything downstream of it is here.
@MainActor
struct PlayerInterruptionTests {

    // MARK: - Something else takes the audio

    @Test("An interruption pauses the audio", arguments: SourceKind.allCases)
    func interruptionPauses(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)

        centre.interrupt()
        #expect(!centre.isPlaying)
        #expect(centre.isRunning, "still a session, so the bar stays and the play button works")
        #expect(source.calls.last == .pause)
    }

    @Test("Audio given back carries on by itself", arguments: SourceKind.allCases)
    func audioGivenBackResumes(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)

        centre.interrupt()
        #expect(centre.endingInterruption(mayResume: true) == .resume)
        centre.resumeAfterInterruption()
        #expect(centre.isPlaying)
        #expect(source.calls.last == .play)
    }

    /// The half that is easy to get wrong: a notification arriving during a deliberate pause
    /// must not turn it into one that resumes on its own.
    @Test("A pause the listener made is never undone", arguments: SourceKind.allCases)
    func aListenersPauseIsNeverUndone(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)

        centre.toggle()
        centre.interrupt()
        #expect(centre.endingInterruption(mayResume: true) == .nothing)
        centre.resumeAfterInterruption()
        #expect(!centre.isPlaying, "still paused, because the listener paused it")
    }

    /// `audio-playback`: "audio taken for good ends the session and records the position
    /// rather than leaving it paused for ever".
    @Test("Audio taken for good ends the session and writes the position first")
    func audioTakenForGood() {
        let centre = PlayerCentre()
        let recorded = Positions()
        centre.onRecord = { reached in recorded.append(reached.position) }

        let source = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)
        source.advance(toPart: 1, offset: 44)

        #expect(centre.endingInterruption(mayResume: false) == .lost)
        centre.lostAudio()

        #expect(!centre.isRunning)
        #expect(centre.compact == nil, "no controls left for a session nothing can start")
        #expect(recorded.last == .listening(part: 1, partCount: 3, offset: 44, of: 90))
    }

    // MARK: - The route changes

    /// `audio-playback`: headphones removed pauses, "because a book suddenly playing out
    /// loud is never what was intended".
    @Test("Headphones removed pauses", arguments: SourceKind.allCases)
    func routeLostPauses(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)

        centre.routeLost()
        #expect(!centre.isPlaying)
        #expect(source.calls.last == .pause)
    }

    /// "And it does not resume by itself when they are reconnected."
    ///
    /// The mechanism is that the pause is recorded as the *listener's* rather than an
    /// interruption's, so nothing the platform sends afterwards can undo it. Reconnecting
    /// headphones raises no interruption-ended event at all; this asserts the case where
    /// something else does.
    @Test("Reconnecting them does not start the book again", arguments: SourceKind.allCases)
    func routeRegainedDoesNotResume(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)

        centre.routeLost()
        #expect(centre.endingInterruption(mayResume: true) == .nothing)
        centre.resumeAfterInterruption()
        #expect(!centre.isPlaying, "the listener has to press play")
    }

    // MARK: - The platform is told, every time

    /// The lock screen is a step behind whenever a mutation forgets to publish, and that is
    /// the kind of defect nobody reports. So the publish lives inside ``PlayerCentre`` and
    /// this asserts it reaches the platform from each of the paths that change what a
    /// listener would see.
    @Test("Every change reaches the platform")
    func everyChangePublishes() {
        let centre = PlayerCentre()
        let platform = PlatformDouble()
        centre.platform = platform
        let source = PlaybackSourceDouble(.narrated)

        centre.begin(.stub(id: "a", title: "Bone"), source: source)
        #expect(platform.began == 1)
        #expect(platform.publishes >= 1)

        var seen = platform.publishes
        for act in [
            { centre.toggle() },
            { centre.toggle() },
            { centre.skip(.forward) },
            { centre.setSpeed(PlaybackSpeed(1.5)) },
            { centre.play(part: 1) },
            { source.advance(toPart: 2, offset: 3) },
            { centre.interrupt() },
            { centre.resumeAfterInterruption() },
            { centre.routeLost() },
        ] {
            act()
            #expect(platform.publishes > seen, "this change never reached the lock screen")
            seen = platform.publishes
        }

        centre.end()
        #expect(platform.ended == 1)
    }
}

@MainActor
final class PlatformDouble: PlaybackPlatform {
    private(set) var began = 0
    private(set) var publishes = 0
    private(set) var ended = 0

    /// Whether the platform has been asked for the sleep timer's clock, and never asked to
    /// give it back. `nil` until it is asked either way.
    private(set) var sleepClockRunning: Bool?

    func sessionBegan() { began += 1 }
    func published() { publishes += 1 }
    func sessionEnded() { ended += 1 }
    func sleepTimerChanged(isRunning: Bool) { sleepClockRunning = isRunning }
}
