import Foundation
import Testing

import Playback
import StoryArcCore
@testable import ReaderFeature

/// D18: opening a comic or a PDF ends a voice already speaking — a narrated audiobook or an
/// EPUB being read aloud — the way `ebook-reader` requires of any publication opening over
/// one: "the session ends … and the position it reached is recorded before the new
/// publication opens", and the listener is told once.
///
/// **Where this sits beside the seam it depends on.** `PlayerDisplacementTests` pins
/// `PlayerCentre.handover(opening:)` and `displace()` themselves — what counts as a voice,
/// what the notice says, that it arms once. This pins only the wiring this decision adds:
/// that opening a comic or a PDF *asks* before anything else happens. A `PlayerCentre` of its
/// own, not `.shared`, so this suite cannot see another suite's session.
///
/// **Proved able to fail**, per AGENTS.md §5: commenting out the `handover`/`displace` block
/// in `ReaderModel.open(maxPixelSize:)` failed *Opening a comic ends a voice already
/// speaking* by name — `voiceStopped` stayed `.none` and the double's session stayed
/// running. Reverted.
@MainActor
@Suite("Opening a comic or a PDF and the voice behind it")
struct ReaderVoiceHandoverTests {
    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(
                atPath: candidate.appending(path: "manifest.json").path
            ) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    private func comic() -> (Publication, URL) {
        let location = Self.corpus.appending(path: "comics/refused.cb7")
        return (
            Publication(
                identity: PublicationIdentity(normalizedPath: location.path),
                format: .cb7,
                displayTitle: "A Quiet Harbour",
                origin: .inferred
            ),
            location
        )
    }

    /// A book already speaking, on a centre of this suite's own.
    private func speaking(_ centre: PlayerCentre, title: String = "The Long Field") {
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: "/spoken/\(title)"),
            format: .epub,
            displayTitle: title,
            origin: .inferred
        )
        centre.begin(
            SpokenBook(publication: publication, url: URL(fileURLWithPath: "/spoken/\(title)")),
            source: SilentVoice()
        )
    }

    @Test("Opening a comic ends a voice already speaking, and tells the listener once")
    func endsAVoice() async {
        let centre = PlayerCentre()
        speaking(centre)
        let (publication, url) = comic()

        let model = ReaderModel(publication: publication, url: url, centre: centre)
        await model.open(maxPixelSize: 256)

        #expect(centre.book == nil, "The session that was speaking should have ended.")
        #expect(model.voiceStopped.isPending)
        #expect(model.voiceStopped.title == "The Long Field")
    }

    @Test("Opening a comic while nothing speaks owes no word")
    func silentLibraryOwesNothing() async {
        let centre = PlayerCentre()
        let (publication, url) = comic()

        let model = ReaderModel(publication: publication, url: url, centre: centre)
        await model.open(maxPixelSize: 256)

        #expect(model.voiceStopped == .none)
    }

    @Test("The notice is taken once: a second render of the page finds nothing")
    func takenOnce() async {
        let centre = PlayerCentre()
        speaking(centre)
        let (publication, url) = comic()
        let model = ReaderModel(publication: publication, url: url, centre: centre)
        await model.open(maxPixelSize: 256)
        #expect(model.voiceStopped.isPending)

        model.voiceStopped = model.voiceStopped.taken()

        #expect(model.voiceStopped == .none)
    }
}

/// A voice with nowhere for its words to go — this suite only needs it to exist and to stop.
private final class SilentVoice: PlaybackSource {
    var moved: (@MainActor () -> Void)?
    var ended: (@MainActor () -> Void)?
    let parts: [PlaybackPart] = [PlaybackPart(index: 0, title: nil, duration: nil)]
    let place = PlaybackPlace(partIndex: 0, offset: 0)
    let skipUnit: SkipUnit = .sentence
    let unreadablePartCount = 0

    func play() {}
    func pause() {}
    func stop() {}
    func setSpeed(_ speed: PlaybackSpeed) {}
    func seek(toPart index: Int, offset: TimeInterval) {}
    func skip(_ direction: SkipDirection, by interval: TimeInterval) {}
}
