import Testing

@testable import Formats
@testable import ReaderFeature

/// The rules behind the page browser carousel's chapter name and badge, and the
/// slider's ticks. Android's `ChapterBrowserTest` asserts the same table.
@Suite("Chapter browser markers")
struct ChapterBrowserMarkersTests {

    private let markers = [
        ChapterMarker(index: 0, title: "Prologue"),
        ChapterMarker(index: 40, title: nil),
        ChapterMarker(index: 90, title: "12"),
    ]

    @Test("The name above the carousel is the nearest chapter at or before the centred page")
    func chapterLabelIsTheActiveMarker() {
        #expect(ChapterBrowser.chapterLabel(at: 10, markers: markers) == .named("Prologue"))
        #expect(ChapterBrowser.chapterLabel(at: 40, markers: markers) == .position(2))
        #expect(ChapterBrowser.chapterLabel(at: 200, markers: markers) == .named("12"))
    }

    @Test("Before the first chapter starts, the carousel names nothing")
    func chapterLabelBeforeFirstMarkerIsNil() {
        let laterMarkers = [ChapterMarker(index: 5, title: "One")]
        #expect(ChapterBrowser.chapterLabel(at: 0, markers: laterMarkers) == nil)
    }

    @Test("No chapter markers at all draws no name")
    func chapterLabelWithNoMarkersIsNil() {
        #expect(ChapterBrowser.chapterLabel(at: 0, markers: []) == nil)
    }

    @Test("The badge reads a purely numeric title as the chapter's number")
    func badgeReadsANumericTitle() {
        #expect(ChapterBrowser.badgeText(at: 90, markers: markers) == "#12")
    }

    @Test("A title that is not only digits falls back to the chapter's position")
    func badgeFallsBackToPositionForAWordyTitle() {
        #expect(ChapterBrowser.badgeText(at: 0, markers: markers) == "#1")
    }

    @Test("A marker with no title falls back to its position")
    func badgeFallsBackToPositionWithNoTitle() {
        #expect(ChapterBrowser.badgeText(at: 40, markers: markers) == "#2")
    }

    @Test("A page that does not start a chapter carries no badge")
    func badgeIsNilAwayFromAStart() {
        #expect(ChapterBrowser.badgeText(at: 41, markers: markers) == nil)
    }

    @Test("Tick fractions place each chapter start proportionally along the track")
    func tickFractionsAreProportional() {
        let fractions = ChapterBrowser.tickFractions(
            markers: [ChapterMarker(index: 0, title: nil), ChapterMarker(index: 50, title: nil)],
            pageCount: 101
        )
        #expect(fractions == [0.0, 0.5])
    }

    @Test("One page or none gives no ticks to place")
    func tickFractionsEmptyWithOnePage() {
        #expect(ChapterBrowser.tickFractions(markers: markers, pageCount: 1) == [])
        #expect(ChapterBrowser.tickFractions(markers: markers, pageCount: 0) == [])
    }

    @Test("A tick sits where the thumb's centre sits, inset by half the thumb at each end")
    func tickOffsetFollowsTheThumbCentre() {
        #expect(ChapterBrowser.tickOffset(fraction: 0, trackWidth: 300, thumbWidth: 37) == 18.5)
        #expect(ChapterBrowser.tickOffset(fraction: 0.5, trackWidth: 300, thumbWidth: 37) == 150)
        #expect(ChapterBrowser.tickOffset(fraction: 1, trackWidth: 300, thumbWidth: 37) == 281.5)
    }

    @Test("Comic markers come from the archive's declared starts and titles, sorted")
    func comicMarkersAreSortedWithTheirTitles() {
        let built = ChapterBrowser.markers(comicStarts: [40, 0], titles: [0: "Prologue"])
        #expect(built == [
            ChapterMarker(index: 0, title: "Prologue"),
            ChapterMarker(index: 40, title: nil),
        ])
    }

    @Test("PDF markers come from the outline, flattened and deduplicated by page")
    func pdfMarkersFlattenTheOutlineTree() {
        let outline = [
            PdfOutlineItem(
                title: "Part One",
                pageIndex: 0,
                children: [PdfOutlineItem(title: "Chapter 1", pageIndex: 5, children: [])]
            ),
        ]
        let built = ChapterBrowser.markers(pdfOutline: outline)
        #expect(built == [
            ChapterMarker(index: 0, title: "Part One"),
            ChapterMarker(index: 5, title: "Chapter 1"),
        ])
    }
}
