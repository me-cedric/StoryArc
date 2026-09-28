import Testing

@testable import Formats

/// Bounding a container's declared indices against the page list it actually has.
/// Android's `PageDeclarationsTest` asserts the same table.
@Suite("Page declarations")
struct PageDeclarationsTests {
    private let pages = (0..<5).map { PageEntry(path: "\($0).jpg", byteCount: nil) }

    @Test("Every in-range chapter start is kept")
    func inRangeChapterStartsAreKept() {
        #expect(PageDeclarations.chapterStarts(of: pages, declared: [0, 2, 4]) == [0, 2, 4])
    }

    @Test("A chapter start past the page list is dropped, not clamped to the last page")
    func outOfRangeChapterStartIsDropped() {
        #expect(PageDeclarations.chapterStarts(of: pages, declared: [2, 9]) == [2])
    }

    @Test("A negative chapter start is dropped")
    func negativeChapterStartIsDropped() {
        #expect(PageDeclarations.chapterStarts(of: pages, declared: [-1, 3]) == [3])
    }

    @Test("No declared chapters at all is no chapters")
    func noneDeclaredIsEmpty() {
        #expect(PageDeclarations.chapterStarts(of: pages, declared: []).isEmpty)
    }
}
