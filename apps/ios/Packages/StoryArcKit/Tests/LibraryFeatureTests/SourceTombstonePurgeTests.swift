import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// 10.12 and 10.14: what happens around a source's tombstone, through the model that
/// writes and reads it. `SourceRegistryTests` covers the pure logic — what a tombstone
/// carries, and how one is found again. These tests cover the two call sites that use it:
/// removal, which has to capture what the source held before the rows go, and re-adding,
/// which has to find the old tombstone before minting a new identifier.
@Suite("Source tombstones, through the model")
@MainActor
struct SourceTombstonePurgeTests {

    private func sourceStore() -> SourceStore {
        let defaults = UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)")
        return SourceStore(defaults: defaults ?? .standard)
    }

    private func credentialStore() -> CredentialStore {
        CredentialStore(service: "app.storyarc.tests.\(UUID().uuidString)")
    }

    private func catalogue(named name: String = "Comics", locator: String = "https://example.com/feed") -> Source {
        Source(displayName: name, kind: .opdsCatalog, state: .connected, locator: locator)
    }

    private func publication(_ identity: PublicationIdentity, sourceID: UUID) -> Publication {
        Publication(
            identity: identity,
            format: .cbz,
            displayTitle: "Comics 01",
            origin: .inferred,
            sourceID: sourceID
        )
    }

    // MARK: - 10.12: removal captures what the source held

    @Test("Removing a source carries the publications it held into the tombstone")
    func removalCarriesItsPublications() throws {
        let model = LibraryModel(sourceStore: sourceStore())
        let source = catalogue()
        model.add(source)
        let identity = PublicationIdentity(normalizedPath: "/Comics/01.cbz")
        model.publications = [publication(identity, sourceID: source.id)]

        model.remove(source, credentials: credentialStore())

        #expect(model.registry.tombstones.first?.identities == [identity])
    }

    // MARK: - 10.14: re-adding finds the old tombstone

    @Test("Re-adding the same catalogue restores its old identifier and clears the tombstone")
    func readdingRestoresTheOldIdentifier() throws {
        let model = LibraryModel(sourceStore: sourceStore())
        let original = catalogue()
        model.add(original)
        model.remove(original, credentials: credentialStore())
        #expect(model.registry.tombstones.isEmpty == false)

        let fresh = catalogue()
        #expect(fresh.id != original.id)
        model.add(fresh)

        #expect(model.registry[original.id] != nil)
        #expect(model.registry[fresh.id] == nil)
        #expect(model.registry.tombstones.isEmpty)
    }

    /// Task 26.5: the share form, used again for a share in the list, added `127.0.0.1/Sync`
    /// a second time.
    @Test("Adding a place that is already in the list keeps one source, with the reader's name")
    func addingTheSamePlaceTwiceKeepsOneSource() throws {
        let model = LibraryModel(sourceStore: sourceStore())
        let first = catalogue(named: "Comics", locator: "https://example.com/feed")
        model.add(first)
        model.rename(first, to: "My comics")

        model.add(catalogue(named: "Comics", locator: "https://example.com/feed"))

        #expect(model.registry.sources.map(\.id) == [first.id])
        #expect(model.registry[first.id]?.displayName == "My comics")
    }

    @Test("Adding a place again with a new sign-in removes the old secret")
    func addingTheSamePlaceAgainRemovesTheOldSecret() throws {
        let model = LibraryModel(sourceStore: sourceStore())
        let credentials = credentialStore()
        let first = Source(
            displayName: "Comics", kind: .opdsCatalog, state: .connected,
            credentialReference: "old", locator: "https://example.com/feed"
        )
        let again = Source(
            displayName: "Comics", kind: .opdsCatalog, state: .connected,
            credentialReference: "new", locator: "https://example.com/feed"
        )
        #expect(credentials.save("old-token", for: "old"))
        #expect(credentials.save("new-token", for: "new"))
        model.add(first, credentials: credentials)

        model.add(again, credentials: credentials)

        #expect(credentials.secret(for: "old") == nil)
        #expect(credentials.secret(for: "new") == "new-token")
        #expect(model.registry[first.id]?.credentialReference == "new")
    }

    @Test("Adding an unrelated catalogue does not take over another source's tombstone")
    func addingAnUnrelatedSourceMintsItsOwnIdentifier() throws {
        let model = LibraryModel(sourceStore: sourceStore())
        let original = catalogue(named: "Comics", locator: "https://example.com/feed")
        model.add(original)
        model.remove(original, credentials: credentialStore())

        let unrelated = catalogue(named: "Manga", locator: "https://other.example/feed")
        model.add(unrelated)

        #expect(model.registry[unrelated.id] != nil)
        #expect(model.registry.tombstones.contains { $0.sourceID == original.id })
    }

    // MARK: - 10.12: the purge itself

    @Test("Purging an expired tombstone forgets the position of a book nothing else holds")
    func purgeForgetsAnUnheldPosition() async throws {
        let progress = try ProgressStore.inMemory()
        let model = LibraryModel(progress: progress, sourceStore: sourceStore())
        let source = catalogue()
        model.add(source)
        let identity = PublicationIdentity(normalizedPath: "/Comics/01.cbz")
        model.publications = [publication(identity, sourceID: source.id)]
        try await progress.save(
            ReadingProgress(identity: identity, position: .page(index: 3, of: 10), updatedAt: Date())
        )

        model.remove(source, credentials: credentialStore())
        model.publications = []

        await model.purgeExpiredTombstones(at: Date().addingTimeInterval(SourceTombstone.retention + 1))

        #expect(try await progress.progress(for: identity) == nil)
        #expect(model.registry.tombstones.isEmpty)
    }

    @Test("Purging an expired tombstone keeps the position of a book another source still holds")
    func purgeKeepsAPositionStillHeldElsewhere() async throws {
        let progress = try ProgressStore.inMemory()
        let model = LibraryModel(progress: progress, sourceStore: sourceStore())
        let source = catalogue()
        model.add(source)
        let identity = PublicationIdentity(normalizedPath: "/Comics/01.cbz")
        model.publications = [publication(identity, sourceID: source.id)]
        try await progress.save(
            ReadingProgress(identity: identity, position: .page(index: 3, of: 10), updatedAt: Date())
        )

        model.remove(source, credentials: credentialStore())
        // Another source still has the same book on the shelf — a folder copy, say.
        model.publications = [publication(identity, sourceID: UUID())]

        await model.purgeExpiredTombstones(at: Date().addingTimeInterval(SourceTombstone.retention + 1))

        #expect(try await progress.progress(for: identity) != nil)
    }

    @Test("An empty shelf while another source remains defers the purge")
    func emptyShelfDefersThePurge() async throws {
        let progress = try ProgressStore.inMemory()
        let model = LibraryModel(progress: progress, sourceStore: sourceStore())
        let source = catalogue()
        model.add(source)
        model.add(catalogue(named: "Manga", locator: "https://other.example/feed"))
        let identity = PublicationIdentity(normalizedPath: "/Comics/01.cbz")
        model.publications = [publication(identity, sourceID: source.id)]
        try await progress.save(
            ReadingProgress(identity: identity, position: .page(index: 3, of: 10), updatedAt: Date())
        )

        model.remove(source, credentials: credentialStore())
        // A launch with no cached shelf: what the other source holds is not known yet.
        model.publications = []

        await model.purgeExpiredTombstones(at: Date().addingTimeInterval(SourceTombstone.retention + 1))

        #expect(try await progress.progress(for: identity) != nil)
        #expect(model.registry.tombstones.contains { $0.sourceID == source.id })
    }

    @Test("Purging before the thirty days are up forgets nothing")
    func purgeBeforeRetentionForgetsNothing() async throws {
        let progress = try ProgressStore.inMemory()
        let model = LibraryModel(progress: progress, sourceStore: sourceStore())
        let source = catalogue()
        model.add(source)
        let identity = PublicationIdentity(normalizedPath: "/Comics/01.cbz")
        model.publications = [publication(identity, sourceID: source.id)]
        try await progress.save(
            ReadingProgress(identity: identity, position: .page(index: 3, of: 10), updatedAt: Date())
        )

        model.remove(source, credentials: credentialStore())
        model.publications = []

        await model.purgeExpiredTombstones(at: Date())

        #expect(try await progress.progress(for: identity) != nil)
        #expect(model.registry.tombstones.isEmpty == false)
    }
}
