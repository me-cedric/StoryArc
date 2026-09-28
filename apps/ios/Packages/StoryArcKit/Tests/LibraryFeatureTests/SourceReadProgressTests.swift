import Testing

@testable import LibraryFeature

/// What one more page does to a source's continued read.
///
/// `sources`' *More from a source than the library holds*: the source detail states the
/// progress while a read continues, and stops claiming a total once it has one. Every case
/// here is the whole of what decides that — the async loop that calls it
/// (`LibraryModel.continueReadingKavita`) only ever asks it a question and acts on the
/// answer, which is why the loop itself is not asserted directly and this is. Android's
/// `SourceReadProgressTest` asks the same three questions.
struct SourceReadProgressTests {

    @Test("A fresh source starts at page two, with the first slice already counted")
    func started() {
        let progress = SourceReadProgress.started(firstSliceRead: 60)

        #expect(progress.read == 60)
        #expect(progress.total == nil)
        #expect(progress.nextPage == 2)
    }

    @Test("A full page keeps the read going, past the page it just answered")
    func continuing() {
        let progress = SourceReadProgress(read: 60, total: 215, nextPage: 2)

        let step = progress.advancing(pageRequested: 2, unitsRead: 60, holdsMore: true)

        #expect(step == .continuing(SourceReadProgress(read: 120, total: 215, nextPage: 3)))
    }

    @Test("A short page ends the read, with what it added still counted")
    func finished() {
        let progress = SourceReadProgress(read: 120, total: 215, nextPage: 3)

        let step = progress.advancing(pageRequested: 3, unitsRead: 34, holdsMore: false)

        #expect(step == .finished(SourceReadProgress(read: 154, total: 215, nextPage: 4)))
    }

    @Test("A page that is not the one waited on changes nothing")
    func stale() {
        // Two readers of the same source overlapping — a pull-to-refresh landing while a
        // continuation is already past page two. The second one's answer for a page
        // already left behind must not be folded in on top of the one that came after it.
        let progress = SourceReadProgress(read: 180, total: 215, nextPage: 4)

        let step = progress.advancing(pageRequested: 2, unitsRead: 60, holdsMore: true)

        #expect(step == .stale)
    }
}
