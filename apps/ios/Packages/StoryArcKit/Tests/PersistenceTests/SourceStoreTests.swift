import Foundation
import Testing

import StoryArcCore
@testable import Persistence

/// What the source registry keeps across a launch, and what it deliberately does not.
@Suite("Source store")
struct SourceStoreTests {

    private func store() -> SourceStore {
        // A suite of its own per test, so one test's sources are not another's.
        let defaults = UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)")
        return SourceStore(defaults: defaults ?? .standard)
    }

    @Test("An empty store reports an empty registry rather than failing")
    func emptyStore() {
        #expect(store().registry().sources.isEmpty)
    }

    @Test("Order survives a save and a read, because order carries meaning")
    func orderSurvives() {
        // `sources`: the combined library "lists titles from higher sources first when two
        // sources hold the same publication". A store that returned a set would lose that.
        let store = store()
        let registry = SourceRegistry()
            .adding(Source(displayName: "Comics", kind: .localFolder))
            .adding(Source(displayName: "Kavita", kind: .kavitaServer))
            .adding(Source(displayName: "Books", kind: .opdsCatalog))
        store.save(registry)

        #expect(store.registry().sources.map(\.displayName) == ["Comics", "Kavita", "Books"])
    }

    @Test("A source keeps its identifier, so its progress and credentials still resolve")
    func identifierSurvives() {
        let store = store()
        let only = Source(displayName: "Kavita", kind: .kavitaServer, credentialReference: "ref")
        store.save(SourceRegistry().adding(only))

        let read = store.registry()[only.id]

        #expect(read?.id == only.id)
        #expect(read?.credentialReference == "ref")
        #expect(read?.kind == .kavitaServer)
    }

    @Test("A tombstone survives, or the thirty-day promise would reset on every launch")
    func tombstoneSurvives() {
        let store = store()
        let only = Source(displayName: "Kavita", kind: .kavitaServer)
        let removed = Date(timeIntervalSince1970: 500)
        store.save(SourceRegistry().adding(only).removing(only.id, at: removed))

        let read = store.registry()

        #expect(read.tombstones.count == 1)
        #expect(read.tombstones.first?.sourceID == only.id)
        #expect(read.tombstones.first?.removedAt == removed)
    }

    @Test("Connection state is not stored, because it describes a network right now")
    func stateIsNotStored() {
        // A state read back from disk is a claim about the past. Loading as `.connecting`
        // is the honest thing to show on a cold launch.
        let store = store()
        let only = Source(displayName: "Kavita", kind: .kavitaServer, state: .connected)
        store.save(SourceRegistry().adding(only))

        #expect(store.registry()[only.id]?.state == .connecting)
    }

    @Test("A reset forgets every source")
    func resets() {
        let store = store()
        store.save(SourceRegistry().adding(Source(displayName: "Comics", kind: .localFolder)))
        store.reset()

        #expect(store.registry().sources.isEmpty)
    }
}
