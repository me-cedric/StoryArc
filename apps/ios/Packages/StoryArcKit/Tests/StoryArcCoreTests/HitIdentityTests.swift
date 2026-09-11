import Testing

@testable import StoryArcCore

/// That two chapters of one series are two rows, and a written-down sentinel is repaired.
///
/// A keyed list refuses two rows with one key. Two chapters of one series that the server
/// gave neither a title nor a number read alike, so both used to key on
/// `chapter:<series>:` and the search screen drew one row where there were two. Android's
/// `HitIdentityTest` asserts the same table.
@Suite("A row's identity, and a card written before the guard")
struct HitIdentityTests {

    private func chapterHit(_ chapterId: Int, title: String = "") -> KavitaHit {
        KavitaHit(kind: .chapter, title: title, seriesId: 7, chapterId: chapterId)
    }

    private func card(chapterName: String) -> KavitaCard {
        KavitaCard(
            publicationId: "p1",
            downloadId: "d1",
            sourceId: "s1",
            seriesId: 7,
            chapterId: 3,
            seriesName: "Tidal Reach",
            chapterName: chapterName
        )
    }

    @Test("Two nameless chapters of one series are two rows")
    func twoNamelessChapters() {
        #expect(chapterHit(1).id != chapterHit(2).id)
    }

    @Test("One chapter found twice is still one row")
    func oneChapterTwice() {
        #expect(chapterHit(1).id == chapterHit(1).id)
    }

    @Test("A series found by name and through a chapter is still one row")
    func seriesStillFolds() {
        // The fold this identity was written for, and it still folds: a series hit carries
        // no chapter, so nothing finer was added to it.
        let byName = KavitaHit(kind: .series, title: "Green Lantern", seriesId: 7)
        let throughChapter = KavitaHit(kind: .series, title: "Green Lantern", seriesId: 7)
        #expect(byName.id == throughChapter.id)
    }

    @Test("A card written before the guard is repaired when it is read")
    func cardRepaired() {
        // Nothing rewrites a card, so the repair has to happen where it is read.
        #expect(card(chapterName: "-100000").properChapterName == nil)
        #expect(card(chapterName: "100000").properChapterName == nil)
        #expect(card(chapterName: "   ").properChapterName == nil)
        #expect(card(chapterName: "Year One").properChapterName == "Year One")
    }

    @Test("A repaired card lets the file's own title through")
    func fileTitleSurvives() {
        let fromTheFile = Publication(
            identity: PublicationIdentity(normalizedPath: "/books/one.cbz"),
            format: .cbz,
            displayTitle: "Batman: Year One",
            origin: .embedded
        )
        let applied = card(chapterName: "-100000").applied(to: fromTheFile)
        #expect(applied.displayTitle == "Batman: Year One")
    }
}
