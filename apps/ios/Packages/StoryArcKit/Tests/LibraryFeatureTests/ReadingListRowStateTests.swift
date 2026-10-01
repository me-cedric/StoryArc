import Testing

@testable import LibraryFeature

/// `collections-and-reading-lists`' delta: a reading list's row states "finished, part-read
/// with the position reached, or unread — in the same terms the library uses for a
/// publication". ``ReadingListRowState`` is the rule, free of the view so it can be asserted
/// without a window — the same split ``ServerListProgress`` and ``HomeShelfCoverPlan`` make
/// for their own sibling decisions.
@Suite("Reading list row state")
struct ReadingListRowStateTests {

    @Test("An unavailable entry draws nothing and is spoken as unavailable")
    func unavailable() {
        let state = ReadingListRowState.of(isAvailable: false, isFinished: true, fraction: 0.5)
        #expect(state.drawn == nil)
        #expect(!state.spoken.isEmpty)
    }

    @Test("A finished entry draws and speaks the finished word")
    func finished() {
        let state = ReadingListRowState.of(isAvailable: true, isFinished: true, fraction: nil)
        #expect(state.drawn != nil)
        #expect(state.spoken == state.drawn)
    }

    @Test("A part-read entry draws and speaks the percent, not the finished word")
    func partRead() {
        let finished = ReadingListRowState.of(isAvailable: true, isFinished: true, fraction: nil)
        let partRead = ReadingListRowState.of(isAvailable: true, isFinished: false, fraction: 0.4)
        #expect(partRead.drawn != nil)
        #expect(partRead.drawn != finished.drawn)
        #expect(partRead.spoken == partRead.drawn)
    }

    @Test("An unread entry draws nothing, but is still spoken")
    func unread() {
        let state = ReadingListRowState.of(isAvailable: true, isFinished: false, fraction: nil)
        #expect(state.drawn == nil)
        #expect(!state.spoken.isEmpty)
    }

    @Test("Finished wins over a fraction handed in alongside it")
    func finishedWinsOverFraction() {
        let state = ReadingListRowState.of(isAvailable: true, isFinished: true, fraction: 0.1)
        let finishedAlone = ReadingListRowState.of(isAvailable: true, isFinished: true, fraction: nil)
        #expect(state.drawn == finishedAlone.drawn)
    }

    @Test("Unread and unavailable are spoken differently")
    func unreadAndUnavailableDiffer() {
        let unread = ReadingListRowState.of(isAvailable: true, isFinished: false, fraction: nil)
        let unavailable = ReadingListRowState.of(isAvailable: false, isFinished: false, fraction: nil)
        #expect(unread.spoken != unavailable.spoken)
    }
}
