internal import Foundation

internal import StoryArcCore

/// What removing a source takes with it.
///
/// "Remove source" used to begin by looking for the folder behind the source and returning
/// when there was none, so removing a Kavita server or an SMB share did nothing at all: the
/// source stayed in the registry, the app kept using it, and its key stayed in the Keychain
/// with nothing left in the app that would ever look it up again. Rank 8 of the 30 August
/// security review.
///
/// A value rather than a sequence of statements inside the model, so the order — the secret
/// is not conditional on the folder — can be asserted directly. Android's `SourceRemoval`
/// makes the same two answers.
struct SourceRemoval: Equatable {
    /// The secret to forget, or nil when the source never had one.
    ///
    /// The reference the *registry* stored, never one re-derived from the source's id: a
    /// source whose id and credential reference disagree — which every iOS Kavita source's
    /// did — would otherwise keep its key.
    let credentialReference: String?

    /// The folder whose security-scoped access is given back, or nil when the source is not
    /// a folder.
    let folder: URL?

    /// Matched on a folder's own key when `keyOf` can give one, and by name otherwise — a
    /// path is not stable identity on iOS. 10.3: the name is not unique, so a caller that
    /// can resolve the bookmark's own key passes it; a caller that cannot (every existing
    /// test here) still gets the name-matched answer it always did.
    static func of(
        _ source: Source,
        folders: [URL],
        keyOf: (URL) -> String? = { _ in nil }
    ) -> SourceRemoval {
        SourceRemoval(
            credentialReference: source.credentialReference,
            folder: folders.first { keyOf($0) == source.locator }
                ?? folders.first { $0.lastPathComponent == source.locator }
        )
    }
}
