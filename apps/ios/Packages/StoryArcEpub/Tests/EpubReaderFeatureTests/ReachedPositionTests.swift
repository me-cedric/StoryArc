import Foundation
import Testing

import StoryArcCore

@testable import EpubReaderFeature

/// Where a voice reading an EPUB writes down that it got to.
///
/// **Split from the session transitions, which moved to `PlaybackTests`.** The pause table,
/// the handover and the compact bar are shared with a narrated audiobook and live in
/// `Playback` now; this does not. `reading-progress` gives an audiobook an offset in a named
/// part and a reflowable publication a fraction plus an opaque locator, and a publication
/// read aloud is still a reflowable publication — so ``ReachedPosition`` stays beside the
/// reader, and so does its suite.
@Suite("Reached position")
struct ReachedPositionTests {

    private let sentence = #"{"href":"/chapter-4.xhtml","type":"text/html"}"#

    /// The path that can lose an hour. What the session hands the progress store is the
    /// sentence the voice reached, as an opaque locator — never a page number, which a
    /// reflowable book does not have.
    @Test("The reached position is recorded as the sentence, not as a page")
    func reachedPositionIsRecorded() {
        let record = ReachedPosition(locator: sentence, progression: 0.42)
            .record(for: identity, at: moment)
        #expect(record.identity == identity)
        #expect(record.position == .reflowable(progression: 0.42, locator: sentence))
        #expect(record.updatedAt == moment)
        #expect(!record.isFinished)
    }

    /// The end of the publication is the end of the content, not a page count.
    @Test("Listening to the last sentence finishes the book")
    func reachedTheEnd() {
        let end = ReachedPosition(locator: sentence, progression: 1)
        let nearlyThere = ReachedPosition(locator: sentence, progression: 0.9989)
        #expect(end.record(for: identity, at: moment).isFinished)
        #expect(!nearlyThere.record(for: identity, at: moment).isFinished)
    }

    /// A session the process is reclaimed under writes nothing more, so what was written
    /// on the way has to stand on its own — and an empty locator would stand for nothing.
    @Test("A sentence with no locator is not written over a good position")
    func nothingWorthRecording() {
        #expect(!ReachedPosition(locator: "", progression: 0.42).isRecordable)
        #expect(ReachedPosition(locator: sentence, progression: 0).isRecordable)
    }

    private let identity = PublicationIdentity(normalizedPath: "/books/sea-room.epub")
    private let moment = Date(timeIntervalSince1970: 1_700_000_000)
}
