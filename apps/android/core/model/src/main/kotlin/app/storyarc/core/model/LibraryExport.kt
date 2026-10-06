package app.storyarc.core.model

/**
 * Everything a [LibraryDocument] carries, as the device holds it.
 *
 * One value rather than eight parameters, because the export reads exactly this set and the
 * import writes exactly this set — and a shape both directions share is a shape that cannot
 * drift apart. The stores stay in `:core:persistence`; this is what they hand over.
 */
data class LibrarySnapshot(
    val sources: SourceRegistry = SourceRegistry(),
    val certificatePins: Map<String, Set<String>> = emptyMap(),
    val shelves: Shelves = Shelves(),
    val pinnedShelves: PinnedShelves = PinnedShelves(),
    val settings: AppSettings = AppSettings(),
    val themes: ShelfMemory = ShelfMemory(),
    val progress: List<ReadingProgress> = emptyList(),
)

/**
 * The document a snapshot becomes.
 *
 * A pure function, which is what lets `LibraryExportTest` assert the bytes rather than the
 * behaviour of a store. iOS's `LibraryExport` writes the same document from the same values.
 */
object LibraryExport {

    /**
     * What this build writes. `library-portability` / *What the document declares*.
     *
     * @param appVersion the app's own version, which only the app layer knows.
     */
    fun document(
        snapshot: LibrarySnapshot,
        appVersion: String,
        writtenAtEpochMillis: Long,
    ): LibraryDocument = LibraryDocument(
        appVersion = appVersion,
        writtenBy = LibraryDocument.THIS_PLATFORM,
        writtenAt = wireMoment(writtenAtEpochMillis),
        library = body(snapshot),
    )

    /**
     * Only a server's shelf is a shelf the server owns, and a server's shelves are fetched
     * rather than remembered — so nothing local is exported for them, the same rule
     * `ShelvesStore` already writes to disk by.
     */
    private fun body(snapshot: LibrarySnapshot) = LibraryBody(
        sources = snapshot.sources.sources.map(::documentSource),
        certificatePins = snapshot.certificatePins.mapValues { it.value.sorted() },
        collections = snapshot.shelves.collections
            .filter { it.origin == ShelfOrigin.Local }
            .map {
                DocumentCollection(
                    id = it.id.toString(),
                    name = it.name,
                    // Sorted for the reason `ShelvesStore` sorts: a set has no order, and two
                    // exports of one library should not differ.
                    members = it.members.sorted(),
                    coverMemberId = it.coverMemberId,
                )
            },
        readingLists = snapshot.shelves.lists
            .filter { it.origin == ShelfOrigin.Local }
            .map {
                DocumentReadingList(
                    id = it.id.toString(),
                    name = it.name,
                    entries = it.entries,
                    coverMemberId = it.coverMemberId,
                )
            },
        pinnedShelves = snapshot.pinnedShelves.tokens,
        settings = DocumentSettings(snapshot.settings),
        readingThemes = DocumentThemes(
            entries = snapshot.themes.entries.map {
                DocumentThemeEntry(
                    scope = it.scope.name.toWireCase(),
                    shelf = it.shelf,
                    settings = DocumentShelfSettings(it.settings),
                )
            },
            customPalette = snapshot.themes.customPalette,
        ),
        progress = snapshot.progress.map {
            DocumentProgress(
                identity = DocumentIdentity(it.identity),
                position = DocumentPosition(it.position),
                isFinished = it.isFinished,
                finishedAt = it.finishedAtEpochMillis?.let(::wireMoment),
                updatedAt = wireMoment(it.updatedAtEpochMillis),
            )
        },
    )

    /**
     * A source with its address and nothing that could unlock it.
     *
     * `library-portability` / *A server in the export*: "its address, its name, its username
     * and its settings travel, and its secret does not". The username is part of the address
     * a [Source.locator] records; the secret lives in the platform secure store and
     * [Source.credentialReference] is only a handle into *this* device's copy of it, which
     * means nothing anywhere else. So the handle does not travel either, and the single bit
     * the other device needs from it — that there was one — travels as
     * [DocumentSource.needsSignIn].
     */
    private fun documentSource(source: Source) = DocumentSource(
        id = source.id.toString(),
        displayName = source.displayName,
        kind = source.kind.name.toWireCase(),
        lastSuccessfulSync = source.lastSuccessfulSyncEpochMillis?.let(::wireMoment),
        locator = source.locator?.let(ExportableAddress::withoutSecret),
        needsSignIn = source.credentialReference != null,
    )
}
