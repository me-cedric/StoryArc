import Foundation
import Testing

@testable import Playback
import StoryArcCore

/// What the system's two audio notifications do to a running session.
///
/// Tasks 3.9 and 4.1. `PlayerInterruptionTests` asserts what ``PlayerCentre`` does once it is
/// told. These raise the notifications themselves, with the `userInfo` the platform fills in,
/// through the observers ``PlaybackAudioSession`` registers. A pause that the decision table
/// gets right and the wiring never reaches is the defect they exist for.
///
/// Both source kinds, because read-aloud and an audiobook share the one audio session: a call
/// that resumes a book must resume a voice by the same code.
@MainActor
struct AudioSessionEventTests {

    // MARK: - userInfo to event

    @Test("An interruption beginning reads as one beginning")
    func interruptionBegan() {
        #expect(AudioSessionEvent(interruption: interruptionInfo(type: AudioSessionEvent.Raw.interruptionBegan))
            == .interruptionBegan)
    }

    @Test("An interruption ending carries whether the platform said to resume")
    func interruptionEnded() {
        let ended = AudioSessionEvent.Raw.interruptionEnded
        #expect(
            AudioSessionEvent(interruption: interruptionInfo(type: ended, options: AudioSessionEvent.Raw.shouldResume))
                == .interruptionEnded(mayResume: true)
        )
        #expect(AudioSessionEvent(interruption: interruptionInfo(type: ended, options: 0))
            == .interruptionEnded(mayResume: false))
        #expect(AudioSessionEvent(interruption: interruptionInfo(type: ended))
            == .interruptionEnded(mayResume: false), "no option key at all means no permission to resume")
    }

    @Test("An interruption with no readable type is ignored")
    func unreadableInterruption() {
        #expect(AudioSessionEvent(interruption: nil) == nil)
        #expect(AudioSessionEvent(interruption: [:]) == nil)
        #expect(AudioSessionEvent(interruption: interruptionInfo(type: 9)) == nil)
    }

    @Test("Only a device going away is a lost route")
    func routeReasons() {
        #expect(AudioSessionEvent(routeChange: routeInfo(AudioSessionEvent.Raw.oldDeviceUnavailable)) == .routeLost)
        #expect(
            AudioSessionEvent(routeChange: routeInfo(AudioSessionEvent.Raw.newDeviceAvailable)) == nil,
            "plugging headphones in must not pause the book"
        )
        #expect(AudioSessionEvent(routeChange: routeInfo(3)) == nil, "a category change is not a lost route")
        #expect(AudioSessionEvent(routeChange: nil) == nil)
    }

    // MARK: - The notification, through the session, to the centre

    /// `audio-playback`: headphones removed pauses, and "it does not resume by itself when they
    /// are reconnected".
    @Test(
        "Headphones pulled out pause as the listener, and a new device does not resume",
        arguments: SourceKind.allCases
    )
    func headphonesOutThenIn(_ kind: SourceKind) async {
        let rig = running(kind)
        let (centre, source) = (rig.centre, rig.source)
        defer { rig.audio.end() }

        post(AudioSessionEvent.routeChangeName, routeInfo(AudioSessionEvent.Raw.oldDeviceUnavailable))
        await delivered()
        #expect(!centre.isPlaying, "the headphones came out and the book kept playing")
        #expect(source.calls.last == .pause)

        post(AudioSessionEvent.routeChangeName, routeInfo(AudioSessionEvent.Raw.newDeviceAvailable))
        await delivered()
        #expect(!centre.isPlaying, "a new device started the book")

        post(
            AudioSessionEvent.interruptionName,
            interruptionInfo(type: AudioSessionEvent.Raw.interruptionEnded, options: AudioSessionEvent.Raw.shouldResume)
        )
        await delivered()
        #expect(!centre.isPlaying, "the pause was the listener's, so nothing the platform sends undoes it")
        #expect(source.calls.last == .pause)
    }

    @Test("Plugging headphones in while playing changes nothing", arguments: SourceKind.allCases)
    func headphonesInOnly(_ kind: SourceKind) async {
        let rig = running(kind)
        let (centre, source) = (rig.centre, rig.source)
        defer { rig.audio.end() }

        post(AudioSessionEvent.routeChangeName, routeInfo(AudioSessionEvent.Raw.newDeviceAvailable))
        await delivered()

        #expect(centre.isPlaying)
        #expect(source.calls.last != .pause)
    }

    /// `read-aloud-beyond-the-reader` 4.1: "resumes after a call, not after a listener pause".
    @Test("A call pauses the audio and its end resumes it", arguments: SourceKind.allCases)
    func callThenHangUp(_ kind: SourceKind) async {
        let rig = running(kind)
        let (centre, source) = (rig.centre, rig.source)
        defer { rig.audio.end() }

        post(AudioSessionEvent.interruptionName, interruptionInfo(type: AudioSessionEvent.Raw.interruptionBegan))
        await delivered()
        #expect(!centre.isPlaying)
        #expect(source.calls.last == .pause)

        post(
            AudioSessionEvent.interruptionName,
            interruptionInfo(type: AudioSessionEvent.Raw.interruptionEnded, options: AudioSessionEvent.Raw.shouldResume)
        )
        await delivered()
        #expect(centre.isPlaying, "the call ended and the audio stayed silent")
        #expect(source.calls.last == .play)
    }

    @Test("A call after the listener paused leaves it silent", arguments: SourceKind.allCases)
    func callAfterAListenerPause(_ kind: SourceKind) async {
        let rig = running(kind)
        let (centre, source) = (rig.centre, rig.source)
        defer { rig.audio.end() }
        centre.pause()

        post(AudioSessionEvent.interruptionName, interruptionInfo(type: AudioSessionEvent.Raw.interruptionBegan))
        post(
            AudioSessionEvent.interruptionName,
            interruptionInfo(type: AudioSessionEvent.Raw.interruptionEnded, options: AudioSessionEvent.Raw.shouldResume)
        )
        await delivered()

        #expect(!centre.isPlaying, "the call's end undid the listener's pause")
        #expect(source.calls.last == .pause)
    }

    @Test("An interruption that ends without permission to resume ends the session", arguments: SourceKind.allCases)
    func audioTakenForGood(_ kind: SourceKind) async {
        let rig = running(kind)
        let (centre, source) = (rig.centre, rig.source)
        defer { rig.audio.end() }

        post(AudioSessionEvent.interruptionName, interruptionInfo(type: AudioSessionEvent.Raw.interruptionBegan))
        post(
            AudioSessionEvent.interruptionName,
            interruptionInfo(type: AudioSessionEvent.Raw.interruptionEnded, options: 0)
        )
        await delivered()

        #expect(!centre.isRunning, "the session was left paused for ever")
        #expect(source.calls.last == .stop)
    }

    @Test("Nothing observes once the session ends", arguments: SourceKind.allCases)
    func endedSessionsAreDeaf(_ kind: SourceKind) async {
        let rig = running(kind)
        let (centre, source) = (rig.centre, rig.source)
        rig.audio.end()

        post(AudioSessionEvent.routeChangeName, routeInfo(AudioSessionEvent.Raw.oldDeviceUnavailable))
        await delivered()

        #expect(centre.isPlaying)
        #expect(source.calls.last != .pause)
    }

    // MARK: - Helpers

    /// A session of its own on a sender of its own. Tests run side by side and the
    /// notification centre is global, so a shared sender would carry one test's headphones
    /// into another's book.
    private let sender = NSObject()

    struct Rig {
        let centre: PlayerCentre
        let source: PlaybackSourceDouble
        let audio: PlaybackAudioSession
    }

    private func running(_ kind: SourceKind) -> Rig {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)
        let audio = PlaybackAudioSession(driving: centre, postedBy: sender)
        audio.begin()
        return Rig(centre: centre, source: source, audio: audio)
    }

    private func interruptionInfo(type: UInt, options: UInt? = nil) -> [AnyHashable: Any] {
        var info: [AnyHashable: Any] = [AudioSessionEvent.Spelling.interruptionType: type]
        if let options { info[AudioSessionEvent.Spelling.interruptionOptions] = options }
        return info
    }

    private func routeInfo(_ reason: UInt) -> [AnyHashable: Any] {
        [AudioSessionEvent.Spelling.routeChangeReason: reason]
    }

    private func post(_ name: Notification.Name, _ info: [AnyHashable: Any]) {
        NotificationCenter.default.post(name: name, object: sender, userInfo: info)
    }

    /// The observers hand their work to the main queue, so the test waits for the queue.
    private func delivered() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
