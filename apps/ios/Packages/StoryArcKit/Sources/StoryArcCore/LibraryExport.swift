public import Foundation

/// Everything a ``LibraryDocument`` carries, as the device holds it.
///
/// One value rather than eight parameters, because the export reads exactly this set and the
/// import writes exactly this set — and a shape both directions share is a shape that cannot
/// drift apart. The stores stay in `Persistence`; this is what they hand over.
public struct LibrarySnapshot: Sendable, Equatable {
    public var sources: SourceRegistry
    public var certificatePins: [String: Set<String>]
    public var shelves: Shelves
    public var pinnedShelves: PinnedShelves
    public var settings: AppSettings
    public var themes: ShelfMemory
    public var progress: [ReadingProgress]
    public var covers: [ChosenCover]

    /// The shelves the reader deleted. `library-sync` task 3.4.
    public var removedShelves: [ShelfTombstone]

    /// When each setting last changed, by field name. See ``SettingsStamps``.
    public var settingsChangedAt: [String: Date]

    /// When each theme field last changed, by its filed name. See ``ThemeStamps``.
    public var themesChangedAt: [String: Date]

    /// The publications kept from a Kavita server, by ``PublicationIdentity/stableID``: a
    /// local file with a remembered Kavita origin.
    public var kavitaKept: Set<String>

    public init(
        sources: SourceRegistry = SourceRegistry(),
        certificatePins: [String: Set<String>] = [:],
        shelves: Shelves = Shelves(),
        pinnedShelves: PinnedShelves = PinnedShelves(),
        settings: AppSettings = .defaults,
        themes: ShelfMemory = ShelfMemory(),
        progress: [ReadingProgress] = [],
        covers: [ChosenCover] = [],
        removedShelves: [ShelfTombstone] = [],
        settingsChangedAt: [String: Date] = [:],
        themesChangedAt: [String: Date] = [:],
        kavitaKept: Set<String> = []
    ) {
        self.removedShelves = removedShelves
        self.settingsChangedAt = settingsChangedAt
        self.themesChangedAt = themesChangedAt
        self.kavitaKept = kavitaKept
        self.sources = sources
        self.certificatePins = certificatePins
        self.shelves = shelves
        self.pinnedShelves = pinnedShelves
        self.settings = settings
        self.themes = themes
        self.progress = progress
        self.covers = covers
    }

    /// Whether Kavita owns this position, so a sync document leaves it to Kavita.
    ///
    /// `library-sync` task 3.7: a position Kavita holds goes to Kavita, and a second copy in the
    /// document would be a second truth to disagree with. A server identity on a Kavita source
    /// is Kavita's; so is one whose source is gone but whose id is a Kavita chapter; so is a
    /// kept download, which has a local identity and a remembered origin.
    public func ownedByKavita(_ identity: PublicationIdentity) -> Bool {
        if let server = identity.serverIdentifier {
            let source = sources.sources.first { $0.id == server.sourceID }
            if source?.kind == .kavitaServer { return true }
            if source == nil, server.remoteID.hasPrefix("chapter:") { return true }
        }
        return kavitaKept.contains(identity.stableID)
    }
}

/// The document a snapshot becomes.
///
/// A pure function, which is what lets `LibraryExportTests` assert the bytes rather than the
/// behaviour of a store. Android's `LibraryExport` writes the same document from the same
/// values.
public enum LibraryExport {

    /// What this build writes. `library-portability` / *What the document declares*.
    ///
    /// - Parameter appVersion: the app's own version, which only the app layer knows.
    /// - Parameter secrets: the sealed credentials, when the reader chose to carry them. Sealed
    ///   by ``LibrarySecretSealer``; nil is what the writer does unless it was asked.
    public static func document(
        _ snapshot: LibrarySnapshot,
        appVersion: String,
        writtenAt: Date,
        secrets: LibrarySecrets? = nil
    ) -> LibraryDocument {
        LibraryDocument(
            appVersion: appVersion,
            writtenBy: WritingPlatform.ios,
            writtenAt: writtenAt,
            library: body(of: snapshot, device: nil, previous: nil),
            secrets: secrets
        )
    }

    /// What a sync writes: the export, with no Kavita position and with the device beside each
    /// moment.
    ///
    /// `library-sync` tasks 3.1 and 3.7. It never carries secrets.
    ///
    /// - Parameter device: this install's id. See ``LibrarySyncState``.
    /// - Parameter previous: the document this write replaces. A moment it already carried
    ///   keeps the device it named, because this device only took that change.
    public static func syncDocument(
        _ snapshot: LibrarySnapshot,
        appVersion: String,
        writtenAt: Date,
        device: String,
        previous: LibraryDocument?
    ) -> LibraryDocument {
        var owned = snapshot
        owned.progress = snapshot.progress.filter { !snapshot.ownedByKavita($0.identity) }
        return LibraryDocument(
            appVersion: appVersion,
            writtenBy: WritingPlatform.ios,
            writtenAt: writtenAt,
            library: body(of: owned, device: device, previous: previous?.library)
        )
    }

    /// Only a server's shelf is a shelf the server owns, and a server's shelves are fetched
    /// rather than remembered — so nothing local is exported for them, the same rule
    /// `ShelvesStore` already writes to disk by.
    private static func body(
        of snapshot: LibrarySnapshot,
        device: String?,
        previous: LibraryBody?
    ) -> LibraryBody {
        var settings = DocumentSettings(snapshot.settings)
        settings.changed = ChangeStamps.documentStamps(
            snapshot.settingsChangedAt, previous: previous?.settings.changed, device: device
        )
        return LibraryBody(
            sources: snapshot.sources.sources.map(documentSource),
            certificatePins: snapshot.certificatePins.mapValues { $0.sorted() },
            collections: snapshot.shelves.collections.filter { $0.origin == .local }.map {
                documentCollection($0, previous: previous, device: device)
            },
            readingLists: snapshot.shelves.lists.filter { $0.origin == .local }.map {
                documentList($0, previous: previous, device: device)
            },
            pinnedShelves: snapshot.pinnedShelves.tokens,
            settings: settings,
            readingThemes: DocumentThemes(
                entries: snapshot.themes.entries.map { entry in
                    DocumentThemeEntry(
                        scope: entry.scope.rawValue,
                        shelf: entry.shelf,
                        settings: DocumentShelfSettings(entry.settings)
                    )
                },
                customPalette: snapshot.themes.customPalette,
                changed: ChangeStamps.documentStamps(
                    snapshot.themesChangedAt, previous: previous?.readingThemes.changed, device: device
                )
            ),
            progress: snapshot.progress.map { record in
                let identity = DocumentIdentity(record.identity)
                let before = previous?.progress.first { $0.identity == identity }
                return DocumentProgress(
                    identity: identity,
                    position: DocumentPosition(record.position),
                    isFinished: record.isFinished,
                    finishedAt: record.finishedAt,
                    updatedAt: record.updatedAt,
                    changedBy: ChangeStamps.by(
                        record.updatedAt, previousAt: before?.updatedAt, previousBy: before?.changedBy, device: device
                    )
                )
            },
            // Sorted for the reason collections are: two exports of one library should not
            // differ.
            covers: snapshot.covers.sorted { $0.key < $1.key }.map {
                DocumentCover(key: $0.key, image: $0.image.base64EncodedString())
            },
            removedShelves: tombstones(snapshot.removedShelves, previous: previous, device: device)
        )
    }

    private static func documentCollection(
        _ collection: PublicationCollection,
        previous: LibraryBody?,
        device: String?
    ) -> DocumentCollection {
        let before = previous?.collections.first { $0.id == collection.id }
        return DocumentCollection(
            id: collection.id,
            name: collection.name,
            // Sorted for the reason `ShelvesStore` sorts: a set has no order, and two exports of
            // one library should not differ.
            members: collection.members.sorted(),
            coverMemberId: collection.coverMemberID,
            changedAt: moment(collection.changedAt),
            changedBy: moment(collection.changedAt).flatMap {
                ChangeStamps.by($0, previousAt: before?.changedAt, previousBy: before?.changedBy, device: device)
            }
        )
    }

    private static func documentList(_ list: ReadingList, previous: LibraryBody?, device: String?)
        -> DocumentReadingList {
        let before = previous?.readingLists.first { $0.id == list.id }
        return DocumentReadingList(
            id: list.id,
            name: list.name,
            entries: list.entries,
            coverMemberId: list.coverMemberID,
            changedAt: moment(list.changedAt),
            changedBy: moment(list.changedAt).flatMap {
                ChangeStamps.by($0, previousAt: before?.changedAt, previousBy: before?.changedBy, device: device)
            }
        )
    }

    /// The deletions, or nil when there are none, so an older library keeps its old bytes.
    private static func tombstones(_ removed: [ShelfTombstone], previous: LibraryBody?, device: String?)
        -> [DocumentTombstone]? {
        guard !removed.isEmpty else { return nil }
        return removed.sorted { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }.map { tombstone in
            let before = previous?.removedShelves?.first { $0.id == tombstone.id }
            return DocumentTombstone(
                id: tombstone.id,
                removedAt: whole(tombstone.removedAt),
                removedBy: ChangeStamps.by(
                    tombstone.removedAt, previousAt: before?.removedAt, previousBy: before?.removedBy, device: device
                )
            )
        }
    }

    /// A shelf's moment, or nil for a shelf from before sync, which has none.
    private static func moment(_ date: Date) -> Date? {
        date > Date(timeIntervalSince1970: 0) ? whole(date) : nil
    }

    /// A moment to the whole second, as the document writes it, so a document read back
    /// equals the one that was written.
    private static func whole(_ date: Date) -> Date {
        Date(timeIntervalSince1970: ChangeStamps.seconds(date))
    }

    /// A source with its address and nothing that could unlock it.
    ///
    /// `library-portability` / *A server in the export*: "its address, its name, its username
    /// and its settings travel, and its secret does not". The username is part of the address
    /// a `locator` records; the secret lives in the platform secure store and
    /// ``Source/credentialReference`` is only a handle into *this* device's copy of it, which
    /// means nothing anywhere else. So the handle does not travel either, and the single bit
    /// the other device needs from it — that there was one — travels as ``needsSignIn``.
    private static func documentSource(_ source: Source) -> DocumentSource {
        DocumentSource(
            id: source.id,
            displayName: source.displayName,
            kind: source.kind.rawValue,
            lastSuccessfulSync: source.lastSuccessfulSync,
            locator: source.locator.map(ExportableAddress.withoutSecret),
            needsSignIn: source.credentialReference != nil
        )
    }
}
