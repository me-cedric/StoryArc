import Foundation
import Testing

@testable import Playback

/// What the lock screen offers while a book is read aloud.
///
/// `ebook-reader`, *Background and lock screen*:
///
/// > **THEN** playback continues, and platform media controls show the publication title and
/// > offer play, pause, and sentence skip
///
/// Only the second line of that card was asserted, by `PlaybackTransitionTests`. Which buttons
/// the transport turns on was asserted by nothing, on either platform.
///
/// **The inputs come from a real session, not from literals.** Each case starts a
/// ``PlayerCentre`` on a source of one kind and asks the centre what it reports, so the test
/// fails both when ``TransportCommands`` decides wrongly and when a voice stops reporting
/// itself as a source measured in sentences.
///
/// **What this cannot reach**: `MPRemoteCommandCenter` exists only on iOS and this suite runs
/// on the host, so the assignment of these answers to the platform's own command objects is
/// read by no test. ``NowPlaying`` is the single caller, and the assignment there is one line
/// per command.
///
/// Android asserts the same clause from the other end, over the notification the reader
/// actually presses: `ReadAloudTransportTest`.
@MainActor
struct TransportCommandsTests {

    /// What a session on a source of this kind puts on the lock screen.
    private func offered(_ kind: SourceKind) -> TransportCommands {
        let centre = PlayerCentre()
        centre.begin(.stub(id: "sea-room", title: "Sea Room"), source: PlaybackSourceDouble(kind))
        return TransportCommands.of(
            skipUnit: centre.skipUnit,
            isScrubbable: centre.time.isScrubbable
        )
    }

    @Test("Both sources offer play and pause")
    func bothStartAndStop() {
        for kind in SourceKind.allCases {
            let offered = offered(kind)
            #expect(offered.play, "\(kind) offers no play")
            #expect(offered.pause, "\(kind) offers no pause")
            #expect(offered.togglePlayPause, "\(kind) offers no single play-pause button")
        }
    }

    /// The clause itself: a voice skips by sentence.
    @Test("A voice offers sentence skip")
    func aVoiceSkipsBySentence() {
        #expect(offered(.spoken).skipBySentence)
    }

    /// And offers nothing measured in seconds, because it has no seconds.
    @Test("A voice offers no skip by seconds and no scrubber")
    func aVoiceHasNoSeconds() {
        let offered = offered(.spoken)
        #expect(!offered.skipByTime)
        #expect(!offered.scrub)
    }

    /// The control. A rule that answered "sentence skip, no scrubber" for everything would
    /// satisfy both cases above and take the scrubber away from every audiobook.
    @Test("A narrated file offers seconds and a scrubber instead")
    func aNarratedFileSkipsBySeconds() {
        let offered = offered(.narrated)
        #expect(offered.skipByTime)
        #expect(offered.scrub)
        #expect(!offered.skipBySentence)
    }
}
