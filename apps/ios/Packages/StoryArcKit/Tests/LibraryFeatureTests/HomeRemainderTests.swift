import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What Home can honestly say is left of a publication.
///
/// `home-screen`, *Resuming*: "how much is left is stated in the reader's own terms — pages
/// or time remaining — rather than as a percentage alone". The unit is the substance of that
/// requirement, and the September sweep photographed Home getting it wrong: the hero read
/// `2 pages left` for `Sea Room`, which is an M4B. `ios-home-top.png`.
///
/// **It was not a formatting slip.** `PublicationIndexer.audiobook` stores the *part* count
/// in `pageCount`, deliberately and with its reasons — "a comic missing pages and an
/// audiobook missing a part are the same question" — so the fall-through that estimates
/// pages from a fraction had a number to work with and used it. A chapter index rendered as
/// a page count is a fact about the file turned into a fact about the reading, and nothing
/// in a type system objects.
///
/// **The other unit is not derivable here, and that is why the answer is silence.**
/// `ReadingPosition.listening` carries the offset into the current part and that part's
/// length; it carries nothing about the parts after it, and `Publication` records no
/// duration at all — `PublicationIndexer.audiobook` says so in as many words. A percentage
/// would be a percentage over *parts*, and `reading-progress` asks for one "derived from the
/// total duration", so it would be an equal-length guess presented as a measurement — the
/// one thing `ReadingPosition`'s own `fraction` refuses to do.
///
/// Android reached the same conclusion first and wrote it down at
/// `HomeShelves.pagesRemaining`: "Null, which is the surface saying nothing, rather than a
/// page count invented from a chapter index." This is that decision, mirrored.
///
/// Asserted as a value rather than as prose. `swift build` copies an `.xcstrings` without
/// compiling it, so `String(localized:)` answers with the key itself on the host — the trade
/// `PlayerLabels` documents. The decision is what regresses; the sentence is what the view
/// looks up.
@Suite("What Home says is left")
struct HomeRemainderTests {

    // MARK: - Fixtures

    private func comic(pages: Int?) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/Ashfall/1.cbz"),
            format: .cbz,
            displayTitle: "Ashfall #1",
            origin: .inferred,
            pageCount: pages
        )
    }

    private func book(pages: Int?) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/Harbour/1.epub"),
            format: .epub,
            displayTitle: "Harbour Lights 01",
            origin: .inferred,
            pageCount: pages
        )
    }

    /// `Sea Room`, as the corpus holds it: one M4B whose three parts are recorded in
    /// `pageCount` because that is where `PublicationIndexer.audiobook` puts them.
    private func audiobook(parts: Int?) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/Sea Room.m4b"),
            format: .audiobook,
            displayTitle: "Sea Room",
            origin: .inferred,
            pageCount: parts
        )
    }

    private func record(
        _ publication: Publication,
        _ position: ReadingPosition,
        finished: Bool = false
    ) -> ReadingProgress {
        ReadingProgress(
            identity: publication.identity,
            position: position,
            isFinished: finished,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    // MARK: - An audiobook

    @Test("A listening position is never counted in pages")
    func listeningIsNeverPages() {
        let seaRoom = audiobook(parts: 3)
        let stopped = record(
            seaRoom,
            .listening(part: 0, partCount: 3, offset: 30, of: 600)
        )

        let answer = HomeShelves.remainder(of: seaRoom, record: stopped)

        // The frame: `2 pages left` under a full-width cover of an M4B. The subtraction that
        // produced it is right for a comic and meaningless here.
        #expect(answer != .pages(2))
        #expect(answer == .nothingToSay)
    }

    /// Every part of the book, not only the first: the fall-through that produced the defect
    /// ran off `fraction`, so it gave a different wrong number at every position.
    @Test(
        "No position in an audiobook produces a page count",
        arguments: [0, 1, 2, 3, 4]
    )
    func noListeningPositionProducesPages(part: Int) {
        let seaRoom = audiobook(parts: 5)
        let stopped = record(
            seaRoom,
            .listening(part: part, partCount: 5, offset: 120, of: 900)
        )

        #expect(HomeShelves.remainder(of: seaRoom, record: stopped) == .nothingToSay)
    }

    /// A read-aloud session has no duration at all, which is why `of` is optional. The answer
    /// must not change with it: a position with no total is *less* knowable, not more.
    @Test("A listening position with no duration says nothing either")
    func listeningWithoutADurationSaysNothing() {
        let seaRoom = audiobook(parts: 4)
        let stopped = record(
            seaRoom,
            .listening(part: 1, partCount: 4, offset: 0, of: nil)
        )

        #expect(HomeShelves.remainder(of: seaRoom, record: stopped) == .nothingToSay)
    }

    /// A percentage is the last resort for a book with no page count, and it must not become
    /// the audiobook's answer by the back door: over parts it is an equal-length guess, which
    /// is the shape of estimate this app refuses everywhere else.
    @Test("An audiobook with no part count is not answered with a percentage")
    func anAudiobookIsNotAnsweredWithAPercentage() {
        let seaRoom = audiobook(parts: nil)
        let stopped = record(
            seaRoom,
            .listening(part: 1, partCount: 3, offset: 10, of: 100)
        )

        #expect(HomeShelves.remainder(of: seaRoom, record: stopped) == .nothingToSay)
    }

    // MARK: - Everything the change must not have moved

    @Test("A paged position still counts down in pages")
    func aPagedPositionCountsPages() {
        let ashfall = comic(pages: 24)
        let stopped = record(ashfall, .page(index: 3, of: 24))

        #expect(HomeShelves.remainder(of: ashfall, record: stopped) == .pages(20))
    }

    @Test("The last page of a comic has nothing worth saying")
    func theLastPageSaysNothing() {
        let ashfall = comic(pages: 24)
        let stopped = record(ashfall, .page(index: 23, of: 24))

        #expect(HomeShelves.remainder(of: ashfall, record: stopped) == .nothingToSay)
    }

    @Test("A reflowable position is estimated against the spine count")
    func aReflowablePositionUsesTheSpine() {
        let harbour = book(pages: 200)
        let stopped = record(harbour, .reflowable(progression: 0.25, locator: "x"))

        #expect(HomeShelves.remainder(of: harbour, record: stopped) == .pages(150))
    }

    @Test("A reflowable position with no spine count falls back to a percentage")
    func aReflowablePositionWithoutASpineIsAPercentage() {
        let harbour = book(pages: nil)
        let stopped = record(harbour, .reflowable(progression: 0.4, locator: "x"))

        #expect(HomeShelves.remainder(of: harbour, record: stopped) == .percent(60))
    }

    @Test("A publication with no record has nothing to report")
    func noRecordSaysNothing() {
        #expect(HomeShelves.remainder(of: comic(pages: 24), record: nil) == .nothingToSay)
    }

    @Test("A finished publication has nothing left")
    func aFinishedPublicationSaysNothing() {
        let ashfall = comic(pages: 24)
        let done = record(ashfall, .page(index: 3, of: 24), finished: true)

        #expect(HomeShelves.remainder(of: ashfall, record: done) == .nothingToSay)
    }
}
