import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// What removing a source takes with it.
///
/// Rank 8 of the 30 August security review: "Remove source" was a no-op for every source
/// that was not a folder — the folder lookup gated the whole method — and no production
/// code path had ever called `CredentialStore.remove`. A reader who disconnected a Kavita
/// server or an SMB share kept a working credential on the device for a server they
/// believed was gone.
///
/// A real Keychain rather than a fake, for the reason `CredentialStoreTests` gives: the
/// promise under test is about the platform's secure store, and a test against a dictionary
/// asserts nothing about it. Each test uses a service of its own.
///
/// Android's `SourceRemovalTest` asserts the first four cases in the same order. The rest
/// need a model, and Android's is an `AndroidViewModel` that a JVM unit test cannot build.
@Suite("Source removal decision")
struct SourceRemovalDecisionTests {

    private func folders() -> [URL] {
        [URL(fileURLWithPath: "/tmp/Comics"), URL(fileURLWithPath: "/tmp/Manga")]
    }

    @Test("A server source gives up its secret and names no folder")
    func aServerSource() {
        let source = Source(
            displayName: "Kavita",
            kind: .kavitaServer,
            credentialReference: "3F2504E0",
            locator: "https://kavita.example"
        )

        let removal = SourceRemoval.of(source, folders: folders())

        #expect(removal.credentialReference == "3F2504E0")
        #expect(removal.folder == nil)
    }

    @Test("A folder source names its folder")
    func aFolderSource() {
        let source = Source(displayName: "Comics", kind: .localFolder, locator: "Comics")

        let removal = SourceRemoval.of(source, folders: folders())

        #expect(removal.folder?.lastPathComponent == "Comics")
        #expect(removal.credentialReference == nil)
    }

    @Test("A source with no secret still removes cleanly")
    func aSourceWithNoSecret() {
        // A folder never has one, and a removal that only worked for sources with a
        // credential would be the same bug with the guard moved.
        let source = Source(displayName: "Comics", kind: .localFolder, locator: "Comics")

        #expect(SourceRemoval.of(source, folders: folders()).credentialReference == nil)
    }

    @Test("The secret is the one the registry stored, not one derived from the id")
    func theStoredReference() {
        let source = Source(
            displayName: "NAS",
            kind: .networkShare,
            credentialReference: "a-reference-nothing-else-would-guess",
            locator: "smb://nas.example/comics"
        )

        let removal = SourceRemoval.of(source, folders: folders())

        #expect(removal.credentialReference == "a-reference-nothing-else-would-guess")
        #expect(removal.credentialReference != CredentialStore.reference(for: source.id))
    }
}

/// The same promise, through the model that keeps it.
@Suite("Source removal")
@MainActor
struct SourceRemovalTests {

    private func credentialStore() -> CredentialStore {
        CredentialStore(service: "app.storyarc.tests.\(UUID().uuidString)")
    }

    private func sourceStore() -> SourceStore {
        // A suite of its own, so one test's registry is never another's.
        let defaults = UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)")
        return SourceStore(defaults: defaults ?? .standard)
    }

    private func server(named name: String, reference: String) -> Source {
        Source(
            displayName: name,
            kind: .kavitaServer,
            state: .connected,
            credentialReference: reference,
            locator: "https://kavita.example"
        )
    }

    @Test("Removing a server source forgets its stored secret")
    func removingAServerForgetsItsSecret() throws {
        let credentials = credentialStore()
        let reference = CredentialStore.reference(for: UUID())
        #expect(credentials.save("kavita-api-key", for: reference))

        let model = LibraryModel(sourceStore: sourceStore())
        let source = server(named: "Kavita", reference: reference)
        model.add(source)

        model.remove(source, credentials: credentials)

        #expect(credentials.secret(for: reference) == nil)
    }

    @Test("The secret goes by the reference the registry stored, not one derived from the id")
    func removalUsesTheStoredReference() throws {
        // Kavita's own source used to be filed under a reference minted from one UUID and
        // returned with another, so a removal that re-derived the reference from
        // `source.id` would have missed every iOS Kavita key ever stored.
        let credentials = credentialStore()
        let reference = CredentialStore.reference(for: UUID())
        #expect(credentials.save("kavita-api-key", for: reference))

        let model = LibraryModel(sourceStore: sourceStore())
        let source = server(named: "Kavita", reference: reference)
        #expect(CredentialStore.reference(for: source.id) != reference)
        model.add(source)

        model.remove(source, credentials: credentials)

        #expect(credentials.secret(for: reference) == nil)
    }

    @Test("Removing a server source drops it from the registry")
    func removingAServerDropsIt() throws {
        let model = LibraryModel(sourceStore: sourceStore())
        let source = server(named: "Kavita", reference: CredentialStore.reference(for: UUID()))
        model.add(source)
        #expect(model.registry[source.id] != nil)

        model.remove(source, credentials: credentialStore())

        #expect(model.registry[source.id] == nil)
        // A tombstone, not a discard: `sources` keeps reading progress for thirty days so
        // re-adding the same server restores where the reader stopped.
        #expect(model.registry.tombstones.contains { $0.sourceID == source.id })
    }

    @Test("A source with no secret is removed just the same")
    func aSourceWithoutASecret() throws {
        // A local folder never has one, and a removal that only worked for sources with a
        // credential would be the same bug with the guard moved.
        let model = LibraryModel(sourceStore: sourceStore())
        let folder = Source(displayName: "Comics", kind: .localFolder, locator: "Comics")
        model.add(folder)

        model.remove(folder, credentials: credentialStore())

        #expect(model.registry[folder.id] == nil)
    }

    @Test("A removed source takes its publications off the shelf")
    func removingTakesItsPublicationsWithIt() throws {
        let model = LibraryModel(sourceStore: sourceStore())
        let source = server(named: "Kavita", reference: CredentialStore.reference(for: UUID()))
        model.add(source)

        model.remove(source, credentials: credentialStore())

        #expect(model.publications.allSatisfy { $0.sourceID != source.id })
    }
}
