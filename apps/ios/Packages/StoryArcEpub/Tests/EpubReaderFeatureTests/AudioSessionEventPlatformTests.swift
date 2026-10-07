import AVFoundation
import Foundation
import Testing

@testable import Playback
import StoryArcCore

/// The audio-session tests that need the real `AVAudioSession`, which the host cannot link.
///
/// Tasks 3.9 and 4.1. `AudioSessionEventTests` in `StoryArcKit` raises each notification on the
/// host, with the numbers and spellings written out in ``AudioSessionEvent``. These compare
/// each of those with Apple's constant, and post the real notification, from the real sender,
/// with the real keys, into the real ``PlaybackAudioSession``. They live in this package
/// because it is the one whose tests run on a simulator, in CI as well as here:
/// `pnpm test:ios:epub`.
@MainActor
@Suite("The real audio session")
struct AudioSessionEventPlatformTests {

    /// A source that does nothing, so the test reads only what the session did to the centre.
    @MainActor
    final class Silent: PlaybackSource {
        var moved: (@MainActor () -> Void)?
        var ended: (@MainActor () -> Void)?
        let parts = [PlaybackPart(index: 0, title: "One", duration: 100)]
        let place = PlaybackPlace(partIndex: 0, offset: 0)
        let skipUnit = SkipUnit.time
        let unreadablePartCount = 0
        private(set) var paused = 0
        private(set) var played = 0

        func play() { played += 1 }
        func pause() { paused += 1 }
        func stop() {}
        func setSpeed(_ speed: PlaybackSpeed) {}
        func seek(toPart index: Int, offset: TimeInterval) {}
        func skip(_ direction: SkipDirection, by interval: TimeInterval) {}
    }

    @Test("The raw values written in AudioSessionEvent are Apple's")
    func rawValuesMatch() {
        #expect(AudioSessionEvent.Raw.interruptionBegan == AVAudioSession.InterruptionType.began.rawValue)
        #expect(AudioSessionEvent.Raw.interruptionEnded == AVAudioSession.InterruptionType.ended.rawValue)
        #expect(AudioSessionEvent.Raw.shouldResume == AVAudioSession.InterruptionOptions.shouldResume.rawValue)
        #expect(
            AudioSessionEvent.Raw.oldDeviceUnavailable
                == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
        )
        #expect(
            AudioSessionEvent.Raw.newDeviceAvailable
                == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
        )
    }

    @Test("The spellings the host posts are Apple's")
    func spellingsMatch() {
        #expect(AudioSessionEvent.Spelling.interruption == AVAudioSession.interruptionNotification.rawValue)
        #expect(AudioSessionEvent.Spelling.routeChange == AVAudioSession.routeChangeNotification.rawValue)
        #expect(AudioSessionEvent.Spelling.interruptionType == AVAudioSessionInterruptionTypeKey)
        #expect(AudioSessionEvent.Spelling.interruptionOptions == AVAudioSessionInterruptionOptionKey)
        #expect(AudioSessionEvent.Spelling.routeChangeReason == AVAudioSessionRouteChangeReasonKey)
    }

    /// Headphones out pauses as the listener, and a device arriving does not start it again.
    @Test("The real route-change notification pauses the book, and a new device does not resume it")
    func realRouteChange() async {
        let rig = running()
        let (centre, source) = (rig.centre, rig.source)
        defer { rig.audio.end() }
        let started = source.played

        post(AVAudioSession.routeChangeNotification, [
            AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
        ])
        await delivered()
        #expect(!centre.isPlaying, "the real notification did not reach the session")
        #expect(source.paused == 1)

        post(AVAudioSession.routeChangeNotification, [
            AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue,
        ])
        await delivered()
        #expect(!centre.isPlaying, "a new device started the book")
        #expect(source.played == started)
    }

    /// A call pauses, and hanging up resumes: the voice's clause of task 4.1 on the real keys.
    @Test("The real interruption notifications pause the book, and a hang-up resumes it")
    func realInterruption() async {
        let rig = running()
        let (centre, source) = (rig.centre, rig.source)
        defer { rig.audio.end() }
        let started = source.played

        post(AVAudioSession.interruptionNotification, [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue,
        ])
        await delivered()
        #expect(!centre.isPlaying)

        post(AVAudioSession.interruptionNotification, [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue,
        ])
        await delivered()
        #expect(centre.isPlaying, "the hang-up did not resume the audio")
        #expect(source.played == started + 1)
    }

    struct Rig {
        let centre: PlayerCentre
        let source: Silent
        let audio: PlaybackAudioSession
    }

    private func running() -> Rig {
        let centre = PlayerCentre()
        let source = Silent()
        let book = SpokenBook(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: "/a"),
                format: .epub,
                displayTitle: "Bone",
                origin: .embedded
            ),
            url: URL(fileURLWithPath: "/a")
        )
        centre.begin(book, source: source)
        let audio = PlaybackAudioSession(driving: centre)
        audio.begin()
        return Rig(centre: centre, source: source, audio: audio)
    }

    private func post(_ name: Notification.Name, _ info: [AnyHashable: Any]) {
        NotificationCenter.default.post(name: name, object: AVAudioSession.sharedInstance(), userInfo: info)
    }

    private func delivered() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
