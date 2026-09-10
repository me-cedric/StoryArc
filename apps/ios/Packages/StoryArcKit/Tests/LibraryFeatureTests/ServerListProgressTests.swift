import Testing

@testable import LibraryFeature

/// What a server's two numbers mean about one entry, and about the list they are in.
///
/// `collections-and-reading-lists` asks a reading list to show "how many entries are finished
/// and where the user's position is", and asks each entry to state its own read state. It
/// also asks for nothing to be claimed where a source reports nothing, which is the case this
/// file exists to keep separate: Kavita sends `pagesRead: 0` for an unread entry *and* for an
/// entry it knows nothing about, and only `pagesTotal` tells them apart.
///
/// Android's `ServerListProgressTest` makes the same claims.
struct ServerListProgressTests {

    @Test("Nothing read of a known length is unread")
    func nothingRead() {
        #expect(ServerListProgress.of(pagesRead: 0, pagesTotal: 22) == .unread)
    }

    @Test("Part of a known length carries the position reached")
    func partRead() {
        #expect(ServerListProgress.of(pagesRead: 11, pagesTotal: 22) == .part(percent: 50))
    }

    @Test("Every page of a known length is finished")
    func allRead() {
        #expect(ServerListProgress.of(pagesRead: 22, pagesTotal: 22) == .finished)
    }

    @Test("More pages read than the entry has is still finished")
    func overRead() {
        // Kavita counts a re-read past the end on occasion. It is not 105% read.
        #expect(ServerListProgress.of(pagesRead: 23, pagesTotal: 22) == .finished)
    }

    @Test("No length is the server saying nothing, which is not unread")
    func noLength() {
        #expect(ServerListProgress.of(pagesRead: 0, pagesTotal: 0) == .unknown)
    }

    @Test("A part-read entry never rounds to nothing or to everything")
    func neverRoundsToTheEnds() {
        #expect(ServerListProgress.of(pagesRead: 1, pagesTotal: 400) == .part(percent: 1))
        #expect(ServerListProgress.of(pagesRead: 399, pagesTotal: 400) == .part(percent: 99))
    }

    @Test("The list counts the entries it knows about")
    func listCounts() {
        let counted = ServerListProgress.summary(
            [(0, 22), (11, 22), (22, 22), (22, 22)]
        )

        #expect(counted == ServerListProgress.Counted(finished: 2, of: 4))
    }

    @Test("An entry the server says nothing about is in neither number")
    func unknownIsExcluded() {
        let counted = ServerListProgress.summary([(22, 22), (0, 0), (0, 22)])

        #expect(counted == ServerListProgress.Counted(finished: 1, of: 2))
    }

    @Test("A list the server says nothing about at all counts nothing")
    func nothingKnown() {
        #expect(ServerListProgress.summary([(0, 0), (0, 0)]) == nil)
    }
}
