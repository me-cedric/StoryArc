import Foundation
import Testing

@testable import StoryArcCore

/// A shelf a server told the app about, written down.
///
/// The token is the whole contract: the home surface reads it back after the process that
/// wrote it has gone, so a token that parses differently from the way it was written loses a
/// shelf silently. Case for case with Android's `RememberedShelfTest`, because both platforms
/// write the same strings.
@Suite("Remembered shelves")
struct RememberedShelfTests {

    /// One source, fixed for the life of a test case, so a token compares against itself.
    private let source = UUID()

    private func shelf(
        kind: RememberedShelfKind = .collection,
        serverID: Int = 7,
        title: String = "Image Comics"
    ) -> RememberedShelf {
        RememberedShelf(kind: kind, sourceID: source, serverID: serverID, title: title)
    }

    @Test("A collection round-trips")
    func collectionRoundTrips() {
        let one = shelf()
        #expect(RememberedShelf(token: one.token) == one)
    }

    @Test("A reading list round-trips and is not read back as a collection")
    func listRoundTrips() {
        let one = shelf(kind: .readingList, title: "Crisis, in order")
        let read = RememberedShelf(token: one.token)
        #expect(read == one)
        #expect(read?.kind == .readingList)
    }

    @Test("The two kinds are written down with the words the pins already use")
    func theWords() {
        #expect(shelf().token.hasPrefix("collection:"))
        #expect(shelf(kind: .readingList).token.hasPrefix("list:"))
    }

    @Test("A title holding a colon survives")
    func aColonInTheTitle() {
        #expect(RememberedShelf(token: shelf(title: "Batman: Year One").token)?.title == "Batman: Year One")
    }

    @Test("A title holding spaces survives the stored scalar")
    func spacesSurviveStorage() {
        let one = shelf(title: "To read with my kid")
        #expect(RememberedShelf.shelves(stored: RememberedShelf.stored([one])) == [one])
    }

    @Test("A token this version cannot read is dropped rather than guessed")
    func unreadableTokens() {
        #expect(RememberedShelf(token: "shelf:\(source.uuidString):7:Something") == nil)
        #expect(RememberedShelf(token: "collection:not-a-uuid:7:Something") == nil)
        #expect(RememberedShelf(token: "collection:\(source.uuidString):seven:Something") == nil)
        #expect(RememberedShelf(token: "collection:\(source.uuidString):7:") == nil)
        #expect(RememberedShelf(token: "collection:\(source.uuidString):7") == nil)
        #expect(RememberedShelf(token: "") == nil)
    }

    @Test("A record drops only the tokens it cannot read")
    func aRecordDropsOnlyWhatItCannotRead() {
        let kept = shelf(title: "Kept")
        let read = RememberedShelf.shelves(tokens: [kept.token, "nonsense", "collection:x:1:No"])
        #expect(read == [kept])
    }

    @Test("What is written down is sorted, so two fetches of one set write one value")
    func sorted() {
        let alpha = shelf(serverID: 1, title: "Alpha")
        let beta = shelf(serverID: 2, title: "Beta")
        #expect(RememberedShelf.stored([alpha, beta]) == RememberedShelf.stored([beta, alpha]))
    }

    @Test("Every shelf written survives the trip back")
    func everyShelfSurvives() {
        let shelves = [
            shelf(serverID: 1, title: "Alpha"),
            shelf(kind: .readingList, serverID: 2, title: "Beta: part two")
        ]
        let read = RememberedShelf.shelves(stored: RememberedShelf.stored(shelves))
        #expect(read.sorted { $0.token < $1.token } == shelves.sorted { $0.token < $1.token })
    }
}
