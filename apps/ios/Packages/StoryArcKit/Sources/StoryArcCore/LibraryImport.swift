public import Foundation

/// A document merged into what the device already holds.
///
/// `library-portability` / *Import merges*: the app "merges an import into what the device
/// already holds, record by record", and does not replace the library wholesale. A reader
/// importing onto a device they have been using would lose that device's reading with a
/// replace, and would not be told which.
///
/// Pure, over a ``LibrarySnapshot``, so the rules can be asserted without a store. Android's
/// `LibraryImport` applies the same rules in the same order.
public enum LibraryImport {

    /// What an import would do, with nothing changed.
    public static func plan(_ document: LibraryDocument, onto device: LibrarySnapshot)
        -> LibraryImportPlan {
        let held = Set(device.sources.sources.map(\.id))
        let arriving = document.library.sources.filter { !held.contains($0.id) }

        let shelves = shelvesArriving(document, onto: device)
        let readable = readableProgress(document)
        let progressToAdd = readable.count { heldProgress(for: $0.identity, in: device) == nil }
        let themes = Set(device.themes.entries.map(themeKey))

        return LibraryImportPlan(
            sourcesToAdd: arriving.map(\.displayName),
            sourcesNeedingSignIn: signInsNeeded(document, onto: device),
            shelvesToAdd: shelves.toAdd,
            shelvesToMerge: shelves.toMerge,
            progressToAdd: progressToAdd,
            progressToMerge: readable.count - progressToAdd,
            certificatePinsToAdd: pinsArriving(document, onto: device),
            settingsWillChange: document.library.settings.settings != device.settings,
            themeEntriesToAdd: document.library.readingThemes.entries
                .filter { !themes.contains("\($0.scope)/\($0.shelf ?? "")") }
                .count
        )
    }

    /// Which shelves in the document the device has never seen, and which it can merge into.
    private static func shelvesArriving(_ document: LibraryDocument, onto device: LibrarySnapshot)
        -> (toAdd: [String], toMerge: [ImportedShelf]) {
        let heldCollections = Dictionary(
            device.shelves.collections.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let heldLists = Dictionary(
            device.shelves.lists.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var toAdd: [String] = []
        var toMerge: [ImportedShelf] = []
        for collection in document.library.collections {
            guard let mine = heldCollections[collection.id] else {
                toAdd.append(collection.name)
                continue
            }
            let added = Set(collection.members).subtracting(mine.members).count
            toMerge.append(ImportedShelf(name: mine.name, membersAdded: added))
        }
        for list in document.library.readingLists {
            guard let mine = heldLists[list.id] else {
                toAdd.append(list.name)
                continue
            }
            let added = list.entries.filter { !mine.entries.contains($0) }.count
            toMerge.append(ImportedShelf(name: mine.name, membersAdded: added))
        }
        return (toAdd, toMerge)
    }

    /// The device as the import leaves it, with whatever the merge had to tell the reader.
    public static func merging(_ document: LibraryDocument, into device: LibrarySnapshot)
        -> LibraryImportResult {
        var merged = device

        merged.sources = mergingSources(document, into: device.sources)
        merged.certificatePins = mergingPins(document, into: device.certificatePins)
        merged.shelves = mergingShelves(document, into: device.shelves)
        merged.pinnedShelves = PinnedShelves(
            tokens: device.pinnedShelves.tokens + document.library.pinnedShelves
        )
        // The document's settings win where they differ, because a reader importing their
        // library is asking for the device to look like the one they left. A merge would have
        // to decide per field, and there is no honest rule for "which of two appearances did
        // they mean" — unlike a reading position, where "furthest" is one.
        merged.settings = document.library.settings.settings
        merged.themes = mergingThemes(document, into: device.themes)

        let outcome = mergingProgress(document, into: device)
        merged.progress = outcome.progress

        return LibraryImportResult(snapshot: merged, conflicts: outcome.conflicts)
    }

    // MARK: Sources

    /// A source the device already has is left alone.
    ///
    /// Its state, its secure-store handle and whatever it has learned since belong to this
    /// device. Overwriting a working source with a stale copy of itself would log the reader
    /// out of a server they are signed in to, which is the one thing an import must not do.
    private static func mergingSources(_ document: LibraryDocument, into registry: SourceRegistry)
        -> SourceRegistry {
        let held = Set(registry.sources.map(\.id))
        return document.library.sources
            .filter { !held.contains($0.id) }
            .reduce(registry) { registry, arriving in
                guard let kind = SourceKind(rawValue: arriving.kind) else {
                    // A kind this build does not know is dropped rather than guessed at, the
                    // same rule `SourceStore` already reads its own disk by.
                    return registry
                }
                return registry.adding(
                    Source(
                        id: arriving.id,
                        displayName: arriving.displayName,
                        kind: kind,
                        lastSuccessfulSync: arriving.lastSuccessfulSync,
                        credentialReference: nil,
                        locator: arriving.locator
                    )
                )
            }
    }

    /// Every source the reader will have to sign in to again, by name.
    ///
    /// A source whose secret this device already holds is not one of them, even when the
    /// document says it needed one: the secret the reader is being asked for is the one that
    /// is missing *here*.
    private static func signInsNeeded(_ document: LibraryDocument, onto device: LibrarySnapshot)
        -> [String] {
        let signedIn = Set(
            device.sources.sources.filter { $0.credentialReference != nil }.map(\.id)
        )
        return document.library.sources
            .filter { $0.needsSignIn && !signedIn.contains($0.id) }
            .map(\.displayName)
    }

    // MARK: Certificate pins

    private static func pinsArriving(_ document: LibraryDocument, onto device: LibrarySnapshot)
        -> [CertificatePinNotice] {
        document.library.certificatePins
            .compactMap { host, fingerprints -> CertificatePinNotice? in
                let held = device.certificatePins[host] ?? []
                guard !Set(fingerprints).subtracting(held).isEmpty else { return nil }
                return CertificatePinNotice(host: host, sourceName: sourceNaming(host, in: document))
            }
            .sorted { $0.host < $1.host }
    }

    /// The source in the document whose address points at this host.
    ///
    /// The host is parsed out of the address rather than searched for inside it. `nas.local`
    /// is a substring of `evil-nas.local`, so a search names whichever source sorts first and
    /// can put a trusted name beside a stranger's fingerprint — on the one notice that asks
    /// the reader to accept it.
    private static func sourceNaming(_ host: String, in document: LibraryDocument) -> String? {
        document.library.sources
            .first { hostOf($0.locator) == host }?
            .displayName
    }

    /// The host an address names, or nil where it names none.
    private static func hostOf(_ locator: String?) -> String? {
        locator.flatMap { URL(string: $0)?.host }
    }

    private static func mergingPins(
        _ document: LibraryDocument,
        into held: [String: Set<String>]
    ) -> [String: Set<String>] {
        document.library.certificatePins.reduce(into: held) { merged, pair in
            merged[pair.key, default: []].formUnion(pair.value)
        }
    }

    // MARK: Shelves

    private static func mergingShelves(_ document: LibraryDocument, into shelves: Shelves)
        -> Shelves {
        var merged = shelves
        for arriving in document.library.collections {
            guard let mine = merged.collections.first(where: { $0.id == arriving.id }) else {
                merged = merged.adding(
                    PublicationCollection(
                        id: arriving.id,
                        name: arriving.name,
                        members: Set(arriving.members),
                        coverMemberID: arriving.coverMemberId
                    )
                )
                continue
            }
            merged = merged.adding(Set(arriving.members), to: mine.id)
            // The device's own chosen cover stands; the document's fills a choice never made.
            if mine.coverMemberID == nil, let cover = arriving.coverMemberId {
                merged = merged.settingCover(cover, on: mine.id)
            }
        }
        for arriving in document.library.readingLists {
            guard let mine = merged.lists.first(where: { $0.id == arriving.id }) else {
                merged = merged.adding(
                    ReadingList(
                        id: arriving.id,
                        name: arriving.name,
                        entries: arriving.entries,
                        coverMemberID: arriving.coverMemberId
                    )
                )
                continue
            }
            // Appended rather than interleaved. A reading list's order is the reader's, and
            // there is no rule that can merge two orders without inventing one — so this
            // device's order is kept and whatever it did not have goes on the end.
            merged = merged.appending(
                arriving.entries.filter { !mine.entries.contains($0) },
                to: mine.id
            )
            if mine.coverMemberID == nil, let cover = arriving.coverMemberId {
                merged = merged.settingCover(cover, onList: mine.id)
            }
        }
        return merged
    }

    // MARK: Themes

    /// A choice the device has already made stands.
    ///
    /// The device is the one the reader is holding, and a theme they set on it this morning
    /// should not be undone by a file written last week. What the device has never chosen is
    /// taken from the document, which is the whole point of carrying them.
    private static func mergingThemes(_ document: LibraryDocument, into memory: ShelfMemory)
        -> ShelfMemory {
        let held = Set(memory.entries.map(themeKey))
        var merged = memory
        for arriving in document.library.readingThemes.entries {
            guard let scope = ThemeScope(rawValue: arriving.scope),
                  !held.contains("\(arriving.scope)/\(arriving.shelf ?? "")")
            else { continue }
            merged = merged.recording(
                ShelfMemory.Entry(
                    scope: scope,
                    shelf: arriving.shelf,
                    settings: arriving.settings.settings
                )
            )
        }
        if merged.customPalette == nil {
            merged.customPalette = document.library.readingThemes.customPalette
        }
        return merged
    }

    private static func themeKey(_ entry: ShelfMemory.Entry) -> String {
        "\(entry.scope.rawValue)/\(entry.shelf ?? "")"
    }

    // MARK: Progress

    /// Reading progress through the machinery a server disagreement already goes through.
    ///
    /// ADR-0006's rules, unchanged: the furthest position wins and finished is sticky. An
    /// import is the same problem as a server disagreement, so ``ProgressPull/merging(_:_:)``
    /// decides it rather than a second rule that could drift from the first.
    ///
    /// The document carries no watermark — see ``DocumentProgress`` — so every arriving record
    /// meets a local one that may have none either. That is the case task 1.4 fixed, and this
    /// function is why it had to be fixed first.
    private static func mergingProgress(_ document: LibraryDocument, into device: LibrarySnapshot)
        -> (progress: [ReadingProgress], conflicts: [ProgressPull.Conflict]) {
        let arriving = readableProgress(document)
        let pull = ProgressPull.merging(remote: arriving) { identity in
            heldProgress(for: identity, in: device)
        }

        var merged = device.progress
        for record in pull.toSave {
            if let existing = merged.firstIndex(where: { $0.identity.matches(record.identity) }) {
                merged[existing] = record
            } else {
                merged.append(record)
            }
        }
        return (merged, pull.conflicts)
    }

    /// The records the merge will keep: the one decode step the preview and the merge share.
    ///
    /// A record whose position this build cannot read is dropped here, so the count the
    /// reader is shown is the count that lands. Android's `LibraryImport.readableProgress` is
    /// the same step, and drops the same records for an unreadable position. A date this build
    /// cannot read is refused earlier, by the decoder, for the whole document.
    private static func readableProgress(_ document: LibraryDocument) -> [ReadingProgress] {
        document.library.progress.compactMap { record in
            record.position.position.map { position in
                ReadingProgress(
                    identity: record.identity.identity,
                    position: position,
                    isFinished: record.isFinished,
                    finishedAt: record.finishedAt,
                    updatedAt: record.updatedAt
                )
            }
        }
    }

    private static func heldProgress(for identity: PublicationIdentity, in device: LibrarySnapshot)
        -> ReadingProgress? {
        device.progress.first { $0.identity.matches(identity) }
    }
}

/// The device after an import, and what the merge had to tell the reader.
public struct LibraryImportResult: Sendable, Equatable {
    public var snapshot: LibrarySnapshot

    /// Positions where both sides had moved. `reading-progress` shows these once, naming
    /// both, with the option to take the other — the same notice a server disagreement gets.
    public var conflicts: [ProgressPull.Conflict]

    public init(snapshot: LibrarySnapshot, conflicts: [ProgressPull.Conflict]) {
        self.snapshot = snapshot
        self.conflicts = conflicts
    }
}
