public import Persistence

internal import Catalogue
internal import Foundation
internal import StoryArcCore

/// Moves a catalogue key that an older build saved in the registry into the secure store.
///
/// Before the key went to the Keychain, `?apikey=…` and its kin stayed in the saved locator,
/// which is `UserDefaults`, in the clear, in every backup. `sources` forbids that. A new save
/// already puts the key in the Keychain — see ``CatalogueTarget/storableLocator(for:)`` —
/// and this does the same, once, for a catalogue saved before that.
///
/// Idempotent without a flag: a moved row has no secret in its locator, so a second run finds
/// nothing to do. A row whose move cannot complete stays as it was and is tried again on the
/// next launch, because the key in the locator is still the only copy of it.
public enum CatalogueKeyMigration {
    /// Runs before anything else reads the registry at launch.
    public static func run(_ store: SourceStore, credentials: CredentialStore) {
        let registry = store.registry()
        let moved = migrated(
            registry,
            secret: credentials.secret(for:),
            absent: credentials.isAbsent(_:),
            save: credentials.save(_:for:)
        )
        if moved != registry { store.save(moved) }
    }

    /// The registry with each catalogue's secret query items moved out of its locator.
    ///
    /// The Keychain is three closures so a test can lock it or make a write fail.
    static func migrated(
        _ registry: SourceRegistry,
        secret: (String) -> String?,
        absent: (String) -> Bool,
        save: (String, String) -> Bool
    ) -> SourceRegistry {
        var result = registry
        for source in registry.sources where source.kind == .opdsCatalog {
            guard let locator = source.locator,
                  let url = URL(string: locator),
                  let query = CatalogueTarget.secretQuery(of: url)
            else { continue }

            var credential: OpdsCredential?
            // A reference with no item has no sign-in to keep: the key is stored alone.
            if let reference = source.credentialReference, !absent(reference) {
                // A sign-in that cannot be read now (a locked device) or by this build is kept,
                // not written over.
                guard let stored = secret(reference).flatMap(OpdsCredential.init(stored:)) else { continue }
                credential = stored
            }
            let reference = source.credentialReference ?? CredentialStore.reference(for: source.id)
            guard let value = OpdsCredential.stored(credential, query: query) else { continue }
            guard save(value, reference) else {
                // `CredentialStore.save` removes the old item before it adds the new one.
                if let credential { _ = save(credential.stored, reference) }
                continue
            }

            var moved = source
            moved.locator = CatalogueTarget.storableLocator(for: url)
            moved.credentialReference = reference
            result = result.replacing(moved)
        }
        return result
    }
}
