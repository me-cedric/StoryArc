public import Foundation

/// How an import uses the sealed credentials of a document.
///
/// `library-portability` / *Secrets travel only sealed, and only when asked*. The rules are
/// pure: they say which sources a secret may reach and what the merge does with an opened one,
/// and the `Persistence` layer does the opening and the writing. Android's
/// `LibraryImport.fillableSources` and `merging(secrets:)` are the same rules.
public extension LibraryImport {

    /// The sources whose sealed secret this import would use.
    ///
    /// A secret reaches a source that exists after the merge and that this device holds no
    /// secret for. A source the device is already signed in to keeps its own, for the reason an
    /// existing source is left alone: the copy on this device is the one that works. A held
    /// source with no secret is filled, because that is the secret the reader would be asked for.
    static func fillableSources(_ document: LibraryDocument, onto device: LibrarySnapshot) -> Set<UUID> {
        guard let secrets = document.secrets else { return [] }
        let sealed = Set(secrets.sealed.keys.compactMap { UUID(uuidString: $0) })
        let signedIn = Set(
            device.sources.sources.filter { $0.credentialReference != nil }.map(\.id)
        )
        let kept = Set(
            document.library.sources
                .filter { SourceKind(rawValue: $0.kind) != nil }
                .map(\.id)
        )
        return sealed.intersection(kept).subtracting(signedIn)
    }

    /// Whether the reader has to give a passphrase for this import to carry its secrets.
    static func needsPassphrase(_ document: LibraryDocument, onto device: LibrarySnapshot) -> Bool {
        !fillableSources(document, onto: device).isEmpty
    }

    /// The merge, with opened secrets given to the sources they belong to.
    ///
    /// Each filled source gets the handle `reference` names, and the result lists those sources
    /// in ``LibraryImportResult/credentialed`` so the caller writes the secrets to the secure
    /// store. A source given a secret is no longer listed as needing a sign-in.
    ///
    /// - Parameter secrets: opened secrets by source id. Ids this import cannot use are ignored.
    /// - Parameter reference: the handle the secure store files a source's secret under.
    static func merging(
        _ document: LibraryDocument,
        into device: LibrarySnapshot,
        secrets: [UUID: String],
        reference: (UUID) -> String
    ) -> LibraryImportResult {
        var result = merging(document, into: device)
        let fill = fillableSources(document, onto: device).intersection(secrets.keys)
        var registry = result.snapshot.sources
        var credentialed: Set<UUID> = []
        for id in fill {
            guard var source = registry.sources.first(where: { $0.id == id }) else { continue }
            source.credentialReference = reference(id)
            registry = registry.replacing(source)
            credentialed.insert(id)
        }
        result.snapshot.sources = registry
        result.credentialed = credentialed
        result.sourcesNeedingSignIn = signInsNeeded(document, onto: device, credentialed: credentialed)
        return result
    }
}
