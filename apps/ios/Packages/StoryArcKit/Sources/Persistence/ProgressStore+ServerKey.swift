public import Foundation

public import StoryArcCore

internal import SwiftData

/// How ``ProgressStore`` flattens a server identifier to the one column
/// ``StoredProgress/serverKey`` is, and back.
///
/// Split out of `ProgressStore.swift` at its line cap: encoding, decoding and the one-time
/// re-key are one seam, and every one of them is about this single column.
extension ProgressStore {
    /// A server identifier flattened to one string, so it can be one column.
    static func serverKey(_ identity: PublicationIdentity) -> String? {
        identity.serverIdentifier.map { "\($0.sourceID.uuidString):\($0.remoteID)" }
    }

    /// Two chapter identifiers, two rows — run once, on every open.
    ///
    /// `KavitaOrigin.serverIdentifier` used to record a chapter's remote id as its bare
    /// number, `"42"`, while the library row, the kept card and a pull's own remote record
    /// all built one that reads `"chapter:42"` — `KavitaContributor`, `KavitaFind`. The two
    /// never matched, so a pulled position could never attach to the row a reader had
    /// opened. Every ``StoredProgress/serverKey`` still carrying the bare form is rewritten
    /// here, so no reading position is lost to the rename.
    ///
    /// Idempotent: nothing is left in the old form after the first run, so every open after
    /// that finds nothing to change.
    ///
    /// A `static` function taking the context explicitly, called from `init` before
    /// `self` is fully formed — an instance method here would be actor-isolated and
    /// unreachable from a synchronous, non-`async` initializer.
    static func rekeyLegacyServerKeys(in context: ModelContext) {
        guard let rows = try? context.fetch(FetchDescriptor<StoredProgress>()) else { return }
        var changed = false
        for row in rows {
            guard let key = row.serverKey,
                  let separator = key.firstIndex(of: ":"), separator != key.startIndex
            else { continue }
            let sourcePart = key[key.startIndex..<separator]
            let remote = key[key.index(after: separator)...]
            // The new form is never all digits: a chapter's remote id is "chapter:<n>", an
            // OPDS entry's is "opds:<id>", and anything else already carries a letter.
            guard !remote.isEmpty, remote.allSatisfy(\.isNumber) else { continue }
            row.serverKey = "\(sourcePart):chapter:\(remote)"
            changed = true
        }
        guard changed else { return }
        try? context.save()
    }

    /// The inverse of ``serverKey(_:)``.
    ///
    /// A malformed key yields `nil` rather than throwing: the other two identity
    /// components are still usable, and refusing to read the row would lose a reading
    /// position over a field the store can do without.
    static func serverIdentifier(from key: String?) -> PublicationIdentity.ServerIdentifier? {
        guard let key, let separator = key.firstIndex(of: ":"), separator != key.startIndex,
              let sourceID = UUID(uuidString: String(key[key.startIndex..<separator]))
        else { return nil }
        let remote = String(key[key.index(after: separator)...])
        guard !remote.isEmpty else { return nil }
        return PublicationIdentity.ServerIdentifier(sourceID: sourceID, remoteID: remote)
    }
}
