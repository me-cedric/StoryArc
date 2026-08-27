import Foundation
import Testing

@testable import Persistence

/// Source secrets in the Keychain: stored, read at the moment of use, and removed with
/// the source they belonged to.
///
/// A real Keychain, not a fake. The point of this type is the platform's secure store, and
/// a test against a dictionary would assert nothing about it. Each test uses a service of
/// its own so one test's items are never another's, and cleans up after itself.
@Suite("Credential store")
struct CredentialStoreTests {

    private func store() -> CredentialStore {
        CredentialStore(service: "app.storyarc.tests.\(UUID().uuidString)")
    }

    @Test("A stored secret reads back")
    func roundTrip() {
        let store = store()
        let reference = CredentialStore.reference(for: UUID())

        #expect(store.save("hunter2", for: reference))
        #expect(store.secret(for: reference) == "hunter2")

        store.remove(reference)
    }

    @Test("A reference nobody stored has no secret")
    func missingSecret() {
        #expect(store().secret(for: CredentialStore.reference(for: UUID())) == nil)
    }

    @Test("Saving twice replaces, rather than leaving two items one of which wins")
    func savingTwiceReplaces() {
        // A duplicate item is how a password change appears to work and then does not: the
        // read returns whichever the Keychain hands back first.
        let store = store()
        let reference = CredentialStore.reference(for: UUID())

        store.save("old", for: reference)
        store.save("new", for: reference)

        #expect(store.secret(for: reference) == "new")

        store.remove(reference)
    }

    @Test("Removing a source's secret takes it with it")
    func removes() {
        // `sources` requires removal to take "its stored credentials" with it. A secret
        // outliving its source is a secret nobody will ever look for again.
        let store = store()
        let reference = CredentialStore.reference(for: UUID())
        store.save("hunter2", for: reference)

        #expect(store.remove(reference))
        #expect(store.secret(for: reference) == nil)
    }

    @Test("Removing a secret that is not there succeeds, so removal is idempotent")
    func removingNothingSucceeds() {
        // Source removal calls this whether or not the source had a secret, and a folder
        // never does.
        #expect(store().remove(CredentialStore.reference(for: UUID())))
    }

    @Test("Asking whether a secret exists does not read it")
    func existenceWithoutReading() {
        let store = store()
        let reference = CredentialStore.reference(for: UUID())

        #expect(!store.hasSecret(for: reference))
        store.save("hunter2", for: reference)
        #expect(store.hasSecret(for: reference))

        store.remove(reference)
    }

    @Test("Two sources keep their own secrets")
    func separateItemsPerSource() {
        // One item per source rather than one blob holding all of them: removing a source
        // has to remove exactly its own secret.
        let store = store()
        let first = CredentialStore.reference(for: UUID())
        let second = CredentialStore.reference(for: UUID())
        store.save("first", for: first)
        store.save("second", for: second)

        store.remove(first)

        #expect(store.secret(for: first) == nil)
        #expect(store.secret(for: second) == "second")

        store.remove(second)
    }

    @Test("A reference is the source's identifier and says nothing about the secret")
    func referenceIsOpaque() {
        // `sources`: "the registry entry holds only an opaque reference to it". A reference
        // encoding anything about the secret would be a fact about the secret stored
        // outside the secure store.
        let id = UUID()

        #expect(CredentialStore.reference(for: id) == id.uuidString)
    }
}
