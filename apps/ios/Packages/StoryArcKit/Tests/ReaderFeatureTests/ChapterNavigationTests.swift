import Testing

@testable import ReaderFeature

/// Where the previous or next chapter action goes: within the publication first, and
/// only past its first or last chapter to a neighbouring publication. Android's
/// `ChapterNavigationTest` asserts the same table.
@Suite("Chapter navigation")
struct ChapterNavigationTests {

    @Test("The nearest earlier chapter wins, not the first one declared")
    func previousIsTheNearestBefore() {
        #expect(ChapterNavigation.previousStart(from: 50, starts: [0, 12, 30, 80]) == 30)
    }

    @Test("At or before the first chapter, there is nowhere further back to go")
    func previousAtTheFirstChapterIsNil() {
        #expect(ChapterNavigation.previousStart(from: 12, starts: [12, 30]) == nil)
        #expect(ChapterNavigation.previousStart(from: 5, starts: [12, 30]) == nil)
    }

    @Test("The nearest later chapter wins, not the last one declared")
    func nextIsTheNearestAfter() {
        #expect(ChapterNavigation.nextStart(from: 20, starts: [0, 12, 30, 80]) == 30)
    }

    @Test("At or past the last chapter, there is nowhere further on to go")
    func nextAtTheLastChapterIsNil() {
        #expect(ChapterNavigation.nextStart(from: 30, starts: [12, 30]) == nil)
        #expect(ChapterNavigation.nextStart(from: 90, starts: [12, 30]) == nil)
    }

    @Test("No chapter markers at all is nowhere to go, either direction")
    func noMarkersIsNilEitherWay() {
        #expect(ChapterNavigation.previousStart(from: 10, starts: []) == nil)
        #expect(ChapterNavigation.nextStart(from: 10, starts: []) == nil)
    }
}
