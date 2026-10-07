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

    public init(
        sources: SourceRegistry = SourceRegistry(),
        certificatePins: [String: Set<String>] = [:],
        shelves: Shelves = Shelves(),
        pinnedShelves: PinnedShelves = PinnedShelves(),
        settings: AppSettings = .defaults,
        themes: ShelfMemory = ShelfMemory(),
        progress: [ReadingProgress] = [],
        covers: [ChosenCover] = []
    ) {
        self.sources = sources
        self.certificatePins = certificatePins
        self.shelves = shelves
        self.pinnedShelves = pinnedShelves
        self.settings = settings
        self.themes = themes
        self.progress = progress
        self.covers = covers
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
            library: body(of: snapshot),
            secrets: secrets
        )
    }

    /// Only a server's shelf is a shelf the server owns, and a server's shelves are fetched
    /// rather than remembered — so nothing local is exported for them, the same rule
    /// `ShelvesStore` already writes to disk by.
    private static func body(of snapshot: LibrarySnapshot) -> LibraryBody {
        LibraryBody(
            sources: snapshot.sources.sources.map(documentSource),
            certificatePins: snapshot.certificatePins.mapValues { $0.sorted() },
            collections: snapshot.shelves.collections
                .filter { $0.origin == .local }
                .map { collection in
                    DocumentCollection(
                        id: collection.id,
                        name: collection.name,
                        // Sorted for the reason `ShelvesStore` sorts: a set has no order, and
                        // two exports of one library should not differ.
                        members: collection.members.sorted(),
                        coverMemberId: collection.coverMemberID
                    )
                },
            readingLists: snapshot.shelves.lists
                .filter { $0.origin == .local }
                .map { list in
                    DocumentReadingList(
                        id: list.id,
                        name: list.name,
                        entries: list.entries,
                        coverMemberId: list.coverMemberID
                    )
                },
            pinnedShelves: snapshot.pinnedShelves.tokens,
            settings: DocumentSettings(snapshot.settings),
            readingThemes: DocumentThemes(
                entries: snapshot.themes.entries.map { entry in
                    DocumentThemeEntry(
                        scope: entry.scope.rawValue,
                        shelf: entry.shelf,
                        settings: DocumentShelfSettings(entry.settings)
                    )
                },
                customPalette: snapshot.themes.customPalette
            ),
            progress: snapshot.progress.map { record in
                DocumentProgress(
                    identity: DocumentIdentity(record.identity),
                    position: DocumentPosition(record.position),
                    isFinished: record.isFinished,
                    finishedAt: record.finishedAt,
                    updatedAt: record.updatedAt
                )
            },
            // Sorted for the reason collections are: two exports of one library should not
            // differ.
            covers: snapshot.covers.sorted { $0.key < $1.key }.map {
                DocumentCover(key: $0.key, image: $0.image.base64EncodedString())
            }
        )
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
