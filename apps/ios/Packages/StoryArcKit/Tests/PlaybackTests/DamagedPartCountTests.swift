import Testing

@testable import Playback
import StoryArcCore

/// `PlayerCentre.unreadablePartCount` after a part fails mid-playback. Task 16.5.
///
/// `NarratedSource` itself is the engine `AVPlayer` drives, and a test cannot reach it — the
/// double stands in for the one fact this is about: the source's own count can change after
/// `begin`, and the centre has to notice without being told anything new. `sourceMoved` is
/// the one seam every move already runs through, including the one a decode failure makes.
@MainActor
@Suite("A damaged part's count reaches the player")
struct DamagedPartCountTests {

    @Test("The count at begin is the source's own, read once")
    func countAtBegin() {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(.narrated, unreadableParts: 1)
        centre.begin(.stub(id: "sea-room", title: "Sea Room", format: .m4b), source: source)
        #expect(centre.unreadablePartCount == 1)
    }

    @Test("A part that fails after begin adds itself to the count the player shows")
    func countAfterAFailureDuringPlayback() {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "sea-room", title: "Sea Room", format: .m4b), source: source)
        #expect(centre.unreadablePartCount == 0)

        // The engine's own count changes first — this is what `NarratedSource.fileFailed`
        // does before it moves — and `advance` is the same `moved?()` call a real move
        // past the failed part makes.
        source.unreadablePartCount += 1
        source.advance(toPart: 1, offset: 0)

        #expect(centre.unreadablePartCount == 1)
    }

    @Test("Two failures across a session both reach the player")
    func twoFailuresAcrossASession() {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "sea-room", title: "Sea Room", format: .m4b), source: source)

        source.unreadablePartCount += 1
        source.advance(toPart: 1, offset: 0)
        source.unreadablePartCount += 1
        source.advance(toPart: 2, offset: 0)

        #expect(centre.unreadablePartCount == 2)
    }
}
