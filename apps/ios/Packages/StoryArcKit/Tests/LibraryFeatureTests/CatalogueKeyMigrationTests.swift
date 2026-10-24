import Foundation
import Testing

@testable import LibraryFeature
import Catalogue
import Persistence
import StoryArcCore

/// A catalogue key that an older build left in the registry moves to the secure store once.
@Suite("Catalogue key migration")
struct CatalogueKeyMigrationTests {
    /// The Keychain as a dictionary, with locked items and a write that can be made to fail.
    ///
    /// A locked item reads as nil but is not absent. `save` removes the old value first, as
    /// `CredentialStore.save` does.
    final class Keychain {
        var items: [String: String] = [:]
        var locked: Set<String> = []
        var writes = 0
        var refuses = false

        func migrated(_ registry: SourceRegistry) -> SourceRegistry {
            CatalogueKeyMigration.migrated(registry, secret: {
                self.locked.contains($0) ? nil : self.items[$0]
            }, absent: {
                self.items[$0] == nil && !self.locked.contains($0)
            }, save: { value, reference in
                self.writes += 1
                self.items[reference] = nil
                guard !self.refuses || !value.hasPrefix("query") else { return false }
                self.items[reference] = value
                return true
            })
        }
    }

    func catalogue(_ locator: String, reference: String? = nil) -> Source {
        Source(displayName: "Books", kind: .opdsCatalog, credentialReference: reference, locator: locator)
    }

    @Test("A legacy key moves to the Keychain and leaves the locator")
    func aLegacyKeyMoves() throws {
        let keychain = Keychain()
        let source = catalogue("https://books.example/opds?shelf=comics&ApiKey=k1")

        let moved = try #require(keychain.migrated(SourceRegistry(sources: [source]))[source.id])

        let reference = CredentialStore.reference(for: source.id)
        #expect(moved.locator == "https://books.example/opds?shelf=comics")
        #expect(moved.credentialReference == reference)
        #expect(keychain.items[reference] == "query\nApiKey=k1\n")
    }

    @Test("A key joins the sign-in already in the Keychain")
    func aKeyJoinsTheSignIn() throws {
        let keychain = Keychain()
        keychain.items["ref"] = OpdsCredential.basic(user: "ada", password: "pw").stored
        let source = catalogue("https://books.example/opds?token=t2", reference: "ref")

        let moved = try #require(keychain.migrated(SourceRegistry(sources: [source]))[source.id])

        let stored = try #require(keychain.items["ref"])
        #expect(moved.locator == "https://books.example/opds")
        #expect(moved.credentialReference == "ref")
        #expect(OpdsCredential(stored: stored) == .basic(user: "ada", password: "pw"))
        #expect(OpdsCredential.query(stored: stored) == "token=t2")
    }

    @Test("A reference with no item stores the key alone under that reference")
    func aReferenceWithNoItemStoresTheKeyAlone() throws {
        let keychain = Keychain()
        let source = catalogue("https://books.example/opds?apikey=k1", reference: "gone")

        let moved = try #require(keychain.migrated(SourceRegistry(sources: [source]))[source.id])

        #expect(moved.locator == "https://books.example/opds")
        #expect(moved.credentialReference == "gone")
        #expect(keychain.items == ["gone": "query\napikey=k1\n"])
    }

    @Test("A row with no key, or a sign-in that is locked or unreadable, is left alone")
    func aCleanRowIsLeftAlone() {
        let keychain = Keychain()
        keychain.items = ["ref": "unknown", "locked": OpdsCredential.bearer(token: "t").stored]
        keychain.locked = ["locked"]
        let registry = SourceRegistry(sources: [
            catalogue("https://books.example/opds?shelf=comics"),
            catalogue("https://books.example/opds?apikey=k1", reference: "ref"),
            catalogue("https://books.example/opds?apikey=k1", reference: "locked"),
        ])

        #expect(keychain.migrated(registry) == registry)
        #expect(keychain.writes == 0)
        #expect(keychain.items == ["ref": "unknown", "locked": OpdsCredential.bearer(token: "t").stored])
    }

    @Test("A Keychain write that fails keeps the key in the row and the sign-in in place")
    func aFailedWriteLosesNothing() {
        let keychain = Keychain()
        keychain.refuses = true
        let signIn = OpdsCredential.bearer(token: "t").stored
        keychain.items["ref"] = signIn
        let registry = SourceRegistry(sources: [
            catalogue("https://books.example/opds?apikey=k1"),
            catalogue("https://books.example/opds?apikey=k2", reference: "ref"),
        ])

        #expect(keychain.migrated(registry) == registry)
        #expect(keychain.items == ["ref": signIn])
    }

    @Test("A second run on the real stores changes nothing")
    func aSecondRunChangesNothing() throws {
        let suite = "app.storyarc.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SourceStore(defaults: defaults)
        let credentials = CredentialStore(service: suite)
        let source = catalogue("https://books.example/opds?apikey=k1")
        let reference = CredentialStore.reference(for: source.id)
        defer { _ = credentials.remove(reference) }
        store.save(SourceRegistry(sources: [source]))
        #expect(credentials.isAbsent(reference))

        CatalogueKeyMigration.run(store, credentials: credentials)
        let first = store.registry()
        CatalogueKeyMigration.run(store, credentials: credentials)

        #expect(first[source.id]?.locator == "https://books.example/opds")
        #expect(store.registry() == first)
        #expect(credentials.secret(for: reference) == "query\napikey=k1\n")
        #expect(!credentials.isAbsent(reference))
    }
}
