import Foundation
import Testing

@testable import Persistence
@testable import StoryArcCore

@Suite("Shelves store")
struct ShelvesStoreTests {
    private func store() throws -> ShelvesStore {
        let name = "app.storyarc.tests.\(UUID().uuidString)"
        return ShelvesStore(defaults: try #require(UserDefaults(suiteName: name)))
    }

    @Test("An empty store has nothing on its shelves")
    func emptyStore() throws {
        #expect(try store().shelves() == Shelves())
    }

    @Test("A collection and a list survive the round trip")
    func roundTrip() throws {
        let store = try store()
        let collectionID = UUID()
        let listID = UUID()
        store.save(
            Shelves()
                .adding(PublicationCollection(id: collectionID, name: "Image Comics"))
                .adding(ReadingList(id: listID, name: "Crossover"))
                .adding(["a", "b"], to: collectionID)
                .settingCover("a", on: collectionID)
                .appending(["c", "a", "b"], to: listID)
        )

        let read = store.shelves()
        #expect(read.collections.first?.members == ["a", "b"])
        #expect(read.collections.first?.coverMemberID == "a")
        // The order is the point of a list, and it has to survive being written down.
        #expect(read.lists.first?.entries == ["c", "a", "b"])
    }

    @Test("A server's groupings are not written")
    func serverGroupingsAreNotStored() throws {
        // They belong to the server and are fetched. A cached copy that outlived a server
        // edit is the stale claim the conflict rule exists to prevent.
        let store = try store()
        store.save(
            Shelves()
                .adding(PublicationCollection(name: "Local", origin: .local))
                .adding(PublicationCollection(name: "Remote", origin: .server(UUID())))
        )
        #expect(store.shelves().collections.map(\.name) == ["Local"])
    }
}
