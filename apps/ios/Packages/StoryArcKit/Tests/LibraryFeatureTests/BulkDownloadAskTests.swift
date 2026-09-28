import Foundation
import Testing

@testable import LibraryFeature

/// What a reader is told before a whole shelf is fetched.
///
/// `collections-and-reading-lists`: downloading a collection or a reading list "states the
/// item count and total size before starting".
///
/// Both numbers have to describe the fetch. Quoting the size of the whole shelf is the easy
/// mistake and the expensive one: a reader with nine of ten issues already on the device would
/// be told the tenth costs ten issues' worth of data, on a train, on a metered connection.
///
/// Android's `BulkDownloadAskTest` asserts these cases one for one.
@Suite("Bulk download ask")
struct BulkDownloadAskTests {

    /// One byte for each publication, so a total says which publications it counted.
    private func weigh(_ ids: Set<String>) -> Int64 { Int64(ids.count) }

    @Test("The count is what would be fetched, not what the shelf holds")
    func countsOnlyWhatIsMissing() throws {
        let ask = try #require(
            BulkDownloadAsk.of(["a", "b", "c"], onDevice: ["a"], weigh: weigh)
        )

        #expect(ask.ids == ["b", "c"])
    }

    @Test("The size is weighed for what would be fetched, not for the whole shelf")
    func weighsOnlyWhatIsMissing() throws {
        var weighed: Set<String> = []
        let ask = try #require(
            BulkDownloadAsk.of(["a", "b", "c"], onDevice: ["a"]) {
                weighed = $0
                return self.weigh($0)
            }
        )

        #expect(weighed == ["b", "c"])
        #expect(ask.bytes == 2)
    }

    @Test("A shelf already on the device is asked nothing")
    func nothingToFetchAsksNothing() {
        #expect(BulkDownloadAsk.of(["a", "b"], onDevice: ["a", "b"], weigh: weigh) == nil)
    }

    @Test("An empty shelf is asked nothing either")
    func anEmptyShelfAsksNothing() {
        #expect(BulkDownloadAsk.of([], onDevice: [], weigh: weigh) == nil)
    }

    @Test("A shelf of which none is on the device is fetched whole")
    func nothingOnTheDeviceFetchesEverything() throws {
        let ask = try #require(BulkDownloadAsk.of(["a", "b"], onDevice: [], weigh: weigh))

        #expect(ask.ids == ["a", "b"])
        #expect(ask.bytes == 2)
    }

    @Test("Nothing is weighed when nothing would be fetched")
    func aRefusedAskWeighsNothing() {
        // The store is asked for a size only when there is a question to put. A weigh on the
        // way to saying "nothing to do" reads every file for an answer nobody is shown.
        var asked = false
        _ = BulkDownloadAsk.of(["a"], onDevice: ["a"]) { _ in
            asked = true
            return 0
        }

        #expect(asked == false)
    }
}
