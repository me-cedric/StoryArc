public import Foundation

public import StoryArcCore

/// Where a source's secret is kept: the Keychain in the app, a dictionary in a test.
public protocol SourceSecretStore: Sendable {
    @discardableResult
    func save(_ secret: String, for reference: String) -> Bool
    func secret(for reference: String) -> String?
    @discardableResult
    func remove(_ reference: String) -> Bool
}

extension CredentialStore: SourceSecretStore {}

/// A document read and planned, with nothing changed yet.
public struct LibraryImportPreview: Sendable, Equatable {
    public let document: LibraryDocument
    public let plan: LibraryImportPlan

    /// Whether the document carries secrets this device would use, so the reader is asked for
    /// the passphrase before they confirm.
    public let needsPassphrase: Bool
}

/// What an import did, for the screen that tells the reader and the app that reloads.
public struct LibraryImportOutcome: Sendable, Equatable {
    /// Positions where both sides had moved. The further one was kept.
    public let conflicts: [ProgressPull.Conflict]

    /// Sources, by name, that still ask for a sign-in.
    public let sourcesNeedingSignIn: [String]

    /// How many secrets went to the secure store.
    public let secretsWritten: Int

    /// The library as the import left it. The app reloads its in-memory copies from this.
    public let snapshot: LibrarySnapshot
}

/// Why an import stopped before it changed anything.
public enum LibraryImportFailure: Error, Sendable, Equatable {
    /// The passphrase did not open the secrets, or it was empty. The reader may try again, or
    /// import without the secrets.
    case passphraseRefused
}

/// Export and import of the library, from the bytes to the stores.
///
/// `library-portability`. The pure rules are in `StoryArcCore`; this reads the stores through
/// ``LibraryArchive``, reads and writes secrets through a ``SourceSecretStore``, and keeps the
/// one promise neither of them can: a failed import leaves the device as it was, secrets
/// included. Android's `LibraryTransfer` is the same three operations.
public struct LibraryTransfer: Sendable {
    private let archive: LibraryArchive
    private let secrets: any SourceSecretStore

    public init(archive: LibraryArchive, secrets: any SourceSecretStore) {
        self.archive = archive
        self.secrets = secrets
    }

    // MARK: Export

    /// The document, as the bytes a reader will put wherever they choose.
    ///
    /// - Parameter passphrase: nil writes no secret. A value seals every stored secret under it;
    ///   the caller has already checked the pair with ``ExportPassphrase/problem(_:confirmation:)``.
    ///   The passphrase is used for the one derivation and kept nowhere.
    public func exportData(
        appVersion: String,
        passphrase: String? = nil,
        at moment: Date = Date()
    ) async throws -> Data {
        let snapshot = try await archive.snapshot()
        let sealed = try passphrase.flatMap { passphrase in
            try LibraryExport.sealedSecrets(for: snapshot, passphrase: passphrase) { source in
                source.credentialReference.flatMap { secrets.secret(for: $0) }
            }
        }
        let document = LibraryExport.document(
            snapshot, appVersion: appVersion, writtenAt: moment, secrets: sealed
        )
        return try LibraryDocumentCoder.encode(document)
    }

    // MARK: Import

    /// Reads a document and states what importing it would do. Changes nothing.
    ///
    /// - Throws: ``LibraryDocumentFailure`` when the document is refused, by name.
    public func preview(_ data: Data) async throws -> LibraryImportPreview {
        let document = try LibraryDocumentCoder.decode(data)
        let device = try await archive.snapshot()
        return LibraryImportPreview(
            document: document,
            plan: LibraryImport.plan(document, onto: device),
            needsPassphrase: LibraryImport.needsPassphrase(document, onto: device)
        )
    }

    /// Merges the document into the library.
    ///
    /// Opens the secrets first, so a wrong passphrase stops here with nothing written. Then the
    /// secrets go to the secure store, then the merged library to its stores. A failure in the
    /// second undoes the first: the device is as it was, and the error is thrown again.
    ///
    /// - Parameter passphrase: nil, or empty, imports everything but the secrets; those sources
    ///   are listed as needing a sign-in.
    /// - Throws: ``LibraryImportFailure/passphraseRefused``, or the store's own failure.
    public func performImport(
        _ preview: LibraryImportPreview,
        passphrase: String?
    ) async throws -> LibraryImportOutcome {
        let document = preview.document
        let opened = try openedSecrets(document, passphrase: passphrase)
        let device = try await archive.snapshot()

        let usable = LibraryImport.fillableSources(document, onto: device)
        var stored: [UUID: String] = [:]
        for (id, secret) in opened where usable.contains(id) {
            if secrets.save(secret, for: CredentialStore.reference(for: id)) { stored[id] = secret }
        }

        let result = LibraryImport.merging(
            document, into: device, secrets: stored, reference: CredentialStore.reference(for:)
        )
        // A secret the merge found no source for is not left behind in the secure store.
        for id in stored.keys where !result.credentialed.contains(id) {
            secrets.remove(CredentialStore.reference(for: id))
        }
        do {
            try await archive.apply(result.snapshot)
        } catch {
            for id in stored.keys { secrets.remove(CredentialStore.reference(for: id)) }
            throw error
        }
        return LibraryImportOutcome(
            conflicts: result.conflicts,
            sourcesNeedingSignIn: result.sourcesNeedingSignIn,
            secretsWritten: result.credentialed.count,
            snapshot: result.snapshot
        )
    }

    private func openedSecrets(_ document: LibraryDocument, passphrase: String?) throws -> [UUID: String] {
        guard let sealed = document.secrets, let passphrase, !passphrase.isEmpty else { return [:] }
        do {
            return try LibrarySecretSealer.open(sealed, passphrase: passphrase)
        } catch {
            throw LibraryImportFailure.passphraseRefused
        }
    }
}
