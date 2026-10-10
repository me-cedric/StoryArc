import Foundation
import Testing

import Playback
import ReadiumNavigator
import ReadiumShared
import StoryArcCore
@testable import EpubReaderFeature

/// Task 6.2: returning to a voice session draws the sentence being spoken *then*.
///
/// `ebook-reader`: "returning resumes at the sentence being spoken then, not at the position
/// from when they left, because the voice did not wait". XCUITest cannot read a decoration
/// inside a `WKWebView`, so the reader is a page that records what it was asked to draw —
/// ``SpokenSentenceFollower`` is the seam. The voice is Readium's real synthesizer over the
/// fixture book; only the engine is a double, so the test decides when each sentence ends.
///
/// Android asserts the same case in `ReadAloudHostTest`.
@MainActor
@Suite("Returning to a voice")
struct SpokenReturnTests {

    /// A reader on screen, reduced to what the session asks of it.
    @MainActor
    final class Page: SpokenSentenceFollower {
        let followedPublicationID: String
        private(set) var drawn: [Locator] = []

        init(showing id: String) { followedPublicationID = id }

        func drawSpokenSentence(_ sentence: Locator) async { drawn.append(sentence) }
        func withdrawSpokenHighlight() {}
    }

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

    /// Waits for `condition`, for at most five seconds.
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<250 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("A reader that adopts the session draws the sentence the voice is on, not the opening one")
    func adoptingDrawsTheSentenceBeingSpoken() async throws {
        let url = Self.corpus.appending(path: "ebooks/fixture.epub")
        let reader = EpubReaderModel(
            publication: StoryArcCore.Publication(
                identity: PublicationIdentity(normalizedPath: url.path),
                format: .epub,
                displayTitle: "fixture.epub",
                origin: .embedded
            ),
            url: url
        )
        await reader.open()
        let opened = try #require(reader.opened)
        let engine = HeldEngine()
        let speech = try #require(
            PublicationSpeechSynthesizer(publication: opened, engineFactory: engine.make)
        )
        // Its own centre and player, not the shared ones. Other suites open readers in this
        // process at the same time, and a reader that opens adopts or displaces the shared session.
        let player = PlayerCentre()
        let centre = ReadAloudCentre(player: player)
        let id = reader.publication.id
        let left = Page(showing: id)

        centre.begin(
            SpokenBook(publication: reader.publication, url: url),
            speaking: SpokenSource(speaking: speech, with: SpokenVoice(), in: opened, from: nil),
            recording: SpokenPosition(identity: reader.publication.identity, readingOrder: [], store: nil),
            drawnBy: left
        )
        defer { player.end() }

        // The opening sentence is drawn on the reader that started the voice. Then it leaves.
        await until { left.drawn.count == 1 }
        let opening = try #require(left.drawn.first, "the opening sentence was never drawn")
        centre.release(left)

        // Two more sentences with nobody drawing.
        engine.finishSentence()
        await until { centre.spoken != nil && centre.spoken != opening }
        let second = try #require(centre.spoken)
        engine.finishSentence()
        await until { centre.spoken != nil && centre.spoken != second }
        let third = try #require(centre.spoken)
        try #require(third != second && third != opening, "the voice never reached a third sentence")

        let returned = Page(showing: id)
        centre.adopt(returned)
        await centre.redrawSpokenSentence()

        #expect(returned.drawn == [third], "the returning reader did not draw the sentence being spoken")
        #expect(left.drawn == [opening], "the reader that left was drawn on")
    }
}
