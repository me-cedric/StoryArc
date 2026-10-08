public import Foundation

/// Why a passphrase pair cannot seal an export.
public enum ExportPassphraseProblem: Sendable, Equatable {
    case empty
    case mismatch
}

public extension LibraryExport {

    /// The sealed credentials of every source that holds one, or nil when none does.
    ///
    /// `library-portability` / *Carrying secrets under a passphrase*: each secret is written
    /// only as ciphertext. The secret is read through `secretFor` at the moment of sealing and
    /// kept nowhere; `StoryArcCore` cannot see the secure store, so the caller hands the reader
    /// in. A source whose handle points at nothing is skipped: it is still exported as needing a
    /// sign-in, which is the truth.
    ///
    /// Android's `LibraryExport.sealedSecrets` is the same rule.
    static func sealedSecrets(
        for snapshot: LibrarySnapshot,
        passphrase: String,
        secretFor: (Source) -> String?
    ) throws -> LibrarySecrets? {
        var secrets: [UUID: String] = [:]
        for source in snapshot.sources.sources where source.credentialReference != nil {
            if let secret = secretFor(source) { secrets[source.id] = secret }
        }
        guard !secrets.isEmpty else { return nil }
        return try LibrarySecretSealer.seal(secrets, passphrase: passphrase)
    }
}

/// The rule for the two passphrase fields on the export sheet.
public enum ExportPassphrase {

    /// What is wrong with the pair, or nil when it can seal an export.
    ///
    /// `library-portability`: "a passphrase twice that matches". An empty value is refused first,
    /// because two empty fields match and seal nothing.
    public static func problem(_ passphrase: String, confirmation: String) -> ExportPassphraseProblem? {
        if passphrase.isEmpty { return .empty }
        if passphrase != confirmation { return .mismatch }
        return nil
    }
}
