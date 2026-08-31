import Testing

internal import StoryArcCore

/// That a reflowable publication says where the reader is in words, and never in pages.
///
/// `ebook-reader`, *Progress display* and *A publication that declares no chapters*:
///
/// > **THEN** one line states how far through the publication they are and how much of the
/// > current chapter is left, in words
/// > …
/// > **THEN** the line states progress through the publication alone rather than naming a
/// > chapter that does not exist
/// > **AND** it does not fall back to a page count, because that is the identity the app
/// > refuses to present
///
/// Android mirrors this suite in `ReadingPositionTest`, case for case, the way the format
/// layer's suites already do — the two readers must say the same thing about the same book.
@Suite("Where the reader is, in words")
struct ReadingPositionLineTests {

    @Test("The percentage is the whole publication, rounded, and clamped to its ends")
    func percentage() {
        #expect(ReadingPositionLine.of(totalProgression: 0, chapter: nil, withinChapter: nil)
            .percentThrough == 0)
        #expect(ReadingPositionLine.of(totalProgression: 0.424, chapter: nil, withinChapter: nil)
            .percentThrough == 42)
        #expect(ReadingPositionLine.of(totalProgression: 0.425, chapter: nil, withinChapter: nil)
            .percentThrough == 43)
        #expect(ReadingPositionLine.of(totalProgression: 1, chapter: nil, withinChapter: nil)
            .percentThrough == 100)
        // A renderer that reports past the end is not a reason to show 140%.
        #expect(ReadingPositionLine.of(totalProgression: 1.4, chapter: nil, withinChapter: nil)
            .percentThrough == 100)
        #expect(ReadingPositionLine.of(totalProgression: -0.2, chapter: nil, withinChapter: nil)
            .percentThrough == 0)
    }

    @Test("A publication that declares no chapters names none, and offers no page count")
    func noNavigation() {
        let position = ReadingPositionLine.of(totalProgression: 0.3, chapter: nil, withinChapter: 0.5)

        #expect(position.chapter == nil)
        #expect(position.chapterRemainder == nil)
        #expect(position.percentThrough == 30)
    }

    @Test("A blank chapter title is no chapter, because Readium reports both")
    func blankChapter() {
        for blank in ["", "   ", "\n"] {
            let position = ReadingPositionLine.of(
                totalProgression: 0.3, chapter: blank, withinChapter: 0.5
            )
            #expect(position.chapter == nil, "\"\(blank)\" is not a chapter title")
            #expect(position.chapterRemainder == nil)
        }
    }

    @Test("A chapter is named as the publication spells it, without its surrounding space")
    func namedChapter() {
        let position = ReadingPositionLine.of(
            totalProgression: 0.3, chapter: "  Chapter Three  ", withinChapter: 0.5
        )

        #expect(position.chapter == "Chapter Three")
    }

    @Test("A chapter with no within-chapter report is named and says nothing more")
    func chapterWithoutProgression() {
        let position = ReadingPositionLine.of(
            totalProgression: 0.3, chapter: "Chapter Three", withinChapter: nil
        )

        #expect(position.chapter == "Chapter Three")
        #expect(position.chapterRemainder == nil)
    }

    /// The bands, measured on what is *left* rather than on what is read.
    ///
    /// Written as a table because the inversion is the mistake this is guarding: a threshold
    /// table against the other quantity passes every boundary test and says the opposite
    /// thing on every page.
    @Test(
        "How much of the chapter is left, in bands",
        arguments: [
            (0.0, ChapterRemainder.justBegun),
            (0.05, ChapterRemainder.justBegun),
            (0.1, ChapterRemainder.justBegun),
            (0.15, ChapterRemainder.moreThanHalfLeft),
            (0.3, ChapterRemainder.moreThanHalfLeft),
            (0.4, ChapterRemainder.aboutHalfLeft),
            (0.5, ChapterRemainder.aboutHalfLeft),
            (0.6, ChapterRemainder.aboutHalfLeft),
            (0.61, ChapterRemainder.lessThanHalfLeft),
            (0.85, ChapterRemainder.lessThanHalfLeft),
            (0.9, ChapterRemainder.nearlyDone),
            (1.0, ChapterRemainder.nearlyDone),
        ]
    )
    func bands(within: Double, expected: ChapterRemainder) {
        #expect(ChapterRemainder.of(withinChapter: within) == expected)
    }

    @Test("A within-chapter report outside 0…1 still lands in a band")
    func bandsAreClamped() {
        #expect(ChapterRemainder.of(withinChapter: -1) == .justBegun)
        #expect(ChapterRemainder.of(withinChapter: 3) == .nearlyDone)
    }

    @Test("Every band names a key of its own")
    func everyBandIsNamed() {
        let keys = Set(ChapterRemainder.allCases.map(\.titleKey))

        #expect(keys.count == ChapterRemainder.allCases.count, "two bands share a name")
        for key in keys {
            #expect(key.hasPrefix("reader.chapter.left."))
        }
    }
}
