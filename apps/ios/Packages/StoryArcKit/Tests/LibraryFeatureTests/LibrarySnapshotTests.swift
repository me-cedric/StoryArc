import Testing

@testable import LibraryFeature

/// When last session's shelf is replaced, and when it is left alone.
///
/// Both refusals are about a reader's next launch. `sources` asks the cached catalogue to
/// make the library "open instantly and stay browsable while offline" — and a cache that
/// overwrites itself with the results of a failed walk delivers the opposite: an empty
/// shelf, dated now.
///
/// Android's `LibrarySnapshotTest` asserts the same four cases.
@Suite("Writing last session's shelf")
struct LibrarySnapshotTests {

    @Test("A finished walk that found something is written")
    func aGoodWalk() {
        #expect(LibrarySnapshot.worthWriting(partial: false, shelf: 12, cached: 8))
    }

    @Test("A partial walk is never written, because it has refreshed nothing")
    func aPartialWalk() {
        #expect(!LibrarySnapshot.worthWriting(partial: true, shelf: 12, cached: 8))
        #expect(!LibrarySnapshot.worthWriting(partial: true, shelf: 12, cached: 0))
    }

    @Test("An empty shelf does not replace a snapshot that holds something")
    func anEmptyShelf() {
        // One unreachable server, or one folder the system stopped granting, would
        // otherwise cost the reader their whole cached library on the next launch.
        #expect(!LibrarySnapshot.worthWriting(partial: false, shelf: 0, cached: 8))
    }

    @Test("An empty shelf with nothing cached is written, because there is nothing to lose")
    func nothingToLose() {
        #expect(LibrarySnapshot.worthWriting(partial: false, shelf: 0, cached: 0))
    }
}
