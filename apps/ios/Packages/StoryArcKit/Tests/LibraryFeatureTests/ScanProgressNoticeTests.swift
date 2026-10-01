import Testing

@testable import LibraryFeature

/// 10.7: the bottom strip states a running scan's count only beside a shelf that has rows.
/// An empty shelf already draws the count, and its Cancel, in the middle of the screen.
@Suite("The scan's count in the bottom strip")
struct ScanProgressNoticeTests {
    @Test("A scan beside a shelf with rows shows its count in the strip")
    func besideRows() {
        #expect(ScanProgressNotice.found(in: .scanning(found: 7), shelfHasRows: true) == 7)
    }

    @Test("A scan over an empty shelf leaves its count to the middle of the screen")
    func overAnEmptyShelf() {
        #expect(ScanProgressNotice.found(in: .scanning(found: 7), shelfHasRows: false) == nil)
    }

    @Test("A finished scan puts no count in the strip")
    func finished() {
        #expect(ScanProgressNotice.found(in: .finished(found: 7, skipped: 0), shelfHasRows: true) == nil)
    }
}
