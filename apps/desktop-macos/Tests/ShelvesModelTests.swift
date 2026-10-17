import Foundation
import StoryArcCore
import Testing

@testable import StoryArc

/// Task 3.15a, test first: collections and reading lists as the Mac draws them.
///
/// `collections-and-reading-lists`: a publication belongs to any number of collections, a
/// reading list keeps the order the reader gave it, an edit made while the server is away is
/// applied locally and marked pending, and pinned shelves come first (`home-screen`).
@Suite("Shelves model")
struct ShelvesModelTests {
    private let comics = UUID()
    private let weekend = UUID()
    private let crossover = UUID()
    private let empty = UUID()

    private var shelves: Shelves {
        Shelves(
            collections: [
                PublicationCollection(id: comics, name: "Comics", members: [id("a"), id("b"), id("gone")]),
                PublicationCollection(id: weekend, name: "Weekend", members: [id("b")]),
                PublicationCollection(id: empty, name: "Empty"),
            ],
            lists: [ReadingList(id: crossover, name: "Crossover", entries: [id("c"), id("a"), id("b")])]
        )
    }

    private func publication(_ name: String, title: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/shelves/\(name).cbz"), format: .cbz, displayTitle: title,
            origin: .inferred
        )
    }

    /// The library id of the fixture named `name`.
    private func id(_ name: String) -> String { publication(name, title: name).id }

    private var library: [Publication] {
        [publication("a", title: "Alpha"), publication("b", title: "Beta"), publication("c", title: "Gamma")]
    }

    @Test("A publication belongs to every collection that holds it, and to none it was not added to")
    func membership() {
        let holding = MacShelves.collections(containing: id("b"), in: shelves)
        #expect(Set(holding.map(\.name)) == ["Comics", "Weekend"])
        #expect(MacShelves.collections(containing: id("c"), in: shelves).isEmpty)
        let adding = MacShelves.adding([id("c")], to: .collection(weekend), in: shelves)
        #expect(Set(MacShelves.collections(containing: id("c"), in: adding).map(\.name)) == ["Weekend"])
    }

    @Test("A collection's members are the publications still in the library, in title order")
    func collectionMembers() {
        let members = MacShelves.members(of: .collection(comics), in: shelves, library: library)
        #expect(members.map(\.displayTitle) == ["Alpha", "Beta"])
    }

    @Test("A reading list keeps the reader's order; a new entry goes to the end and one already there stays")
    func listOrder() {
        let entries = MacShelves.entries(of: crossover, in: shelves, library: library, pending: [])
        #expect(entries.map(\.title) == ["Gamma", "Alpha", "Beta"])
        let appended = MacShelves.adding([id("d"), id("a")], to: .list(crossover), in: shelves)
        #expect(appended.lists.first?.entries == [id("c"), id("a"), id("b"), id("d")])
    }

    @Test("Pinned shelves come first, then the rest by name, and the sidebar names each kind")
    func pinnedOrder() {
        let rows = MacShelves.sidebar(shelves, pins: PinnedShelves([.list(crossover), .collection(weekend)]))
        #expect(rows.map(\.name) == ["Crossover", "Weekend", "Comics", "Empty"])
        #expect(rows.first?.isPinned == true)
        #expect(rows.first?.kind == .list)
        #expect(rows.last?.isPinned == false)
    }

    @Test("An edit made while the server is away is shown, grey, at the end of the list")
    func pendingIsGrey() throws {
        let key = ShelfKey(sourceID: UUID().uuidString, shelfID: 7)
        let pending = [ShelfEdit(shelf: key, entry: "chapter:42", title: "Issue 42", madeAt: Date())]
        let entries = MacShelves.entries(of: crossover, in: shelves, library: library, pending: pending)
        let last = try #require(entries.last)
        #expect(last.title == "Issue 42")
        #expect(last.isPending)
        #expect(entries.dropLast().allSatisfy { !$0.isPending })
    }

    @Test("An entry whose publication is gone stays in its place, unavailable")
    func goneEntry() {
        let list = Shelves(lists: [
            ReadingList(id: crossover, name: "Crossover", entries: [id("a"), id("gone"), id("b")]),
        ])
        let entries = MacShelves.entries(of: crossover, in: list, library: library, pending: [])
        #expect(entries.map(\.isAvailable) == [true, false, true])
    }

    @Test("A reading list states how far through it the reader is: its finished entries")
    func readThrough() {
        #expect(MacShelves.readThrough(crossover, in: shelves, finished: [id("a"), id("gone")]) == 1)
        #expect(MacShelves.readThrough(crossover, in: shelves, finished: []) == 0)
        #expect(MacShelves.readThrough(UUID(), in: shelves, finished: [id("a")]) == 0)
    }

    @Test("A bulk mark changes only what differs, and its undo puts back exactly that")
    func bulkMark() {
        let selection: Set<String> = [id("a"), id("b"), id("c")]
        let marking = BulkSelection.marking(selection, read: true, finished: [id("b")])
        #expect(marking == [id("a"), id("c")])
        let undoing = BulkSelection.marking(marking, read: false, finished: [id("a"), id("b"), id("c")])
        #expect(undoing == marking)
    }

    @Test("Home lists collections and reading lists as two shelves, and leaves out a kind with nothing")
    func homeShelves() {
        let home = MacShelves.home(shelves, pins: PinnedShelves([.collection(weekend)]))
        #expect(home.collections.map(\.name) == ["Weekend", "Comics", "Empty"])
        #expect(home.lists.map(\.name) == ["Crossover"])
        let none = MacShelves.home(Shelves(lists: []), pins: PinnedShelves())
        #expect(none.collections.isEmpty && none.lists.isEmpty)
        #expect(none.isEmpty)
    }
}
