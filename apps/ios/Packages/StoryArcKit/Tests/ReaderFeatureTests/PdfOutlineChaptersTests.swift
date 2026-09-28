import Testing

@testable import Formats
@testable import ReaderFeature

/// A PDF's own outline, read as chapter starts (D4, iOS only — ADR-0012).
@Suite("PDF outline chapters")
struct PdfOutlineChaptersTests {
    private func item(_ title: String, page: Int?, children: [PdfOutlineItem] = []) -> PdfOutlineItem {
        PdfOutlineItem(title: title, pageIndex: page, children: children)
    }

    @Test("Every top-level entry with a page becomes a chapter start")
    func topLevelEntries() {
        let outline = [item("One", page: 0), item("Two", page: 20), item("Three", page: 45)]
        #expect(PdfOutlineChapters.startIndices(outline) == [0, 20, 45])
    }

    @Test("A nested entry counts too — it is still a place to jump to")
    func nestedEntriesCountToo() {
        let outline = [
            item("Part One", page: 0, children: [item("1.1", page: 5), item("1.2", page: 12)]),
        ]
        #expect(PdfOutlineChapters.startIndices(outline) == [0, 5, 12])
    }

    @Test("An entry with no resolvable page is skipped, not a nil in the list")
    func unresolvableEntriesAreSkipped() {
        let outline = [item("Broken", page: nil), item("Fine", page: 3)]
        #expect(PdfOutlineChapters.startIndices(outline) == [3])
    }

    @Test("Two entries that land on the same page count once")
    func duplicatesCollapse() {
        let outline = [item("A", page: 10), item("B", page: 10)]
        #expect(PdfOutlineChapters.startIndices(outline) == [10])
    }

    @Test("No outline at all is no chapters")
    func emptyOutlineIsEmpty() {
        #expect(PdfOutlineChapters.startIndices([]).isEmpty)
    }
}
