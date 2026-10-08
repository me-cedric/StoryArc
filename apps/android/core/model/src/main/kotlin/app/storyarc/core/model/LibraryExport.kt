package app.storyarc.core.model

import java.util.Base64

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
    val covers: List<ChosenCover> = emptyList(),
    /** The shelves the reader deleted. `library-sync` task 3.4. */
    val removedShelves: List<ShelfTombstone> = emptyList(),
    /** When each setting last changed, by field name. See [SettingsStamps]. */
    val settingsChangedAt: Map<String, Long> = emptyMap(),
    /** When each theme field last changed, by its filed name. See [ThemeStamps]. */
    val themesChangedAt: Map<String, Long> = emptyMap(),
    /**
     * The publications kept from a Kavita server, by [PublicationIdentity.stableId]: a local
     * file with a remembered Kavita origin.
     */
    val kavitaKept: Set<String> = emptySet(),
) {
    /**
     * Whether Kavita owns this position, so a sync document leaves it to Kavita.
     *
     * `library-sync` task 3.7: a position Kavita holds goes to Kavita, and a second copy in the
     * document would be a second truth to disagree with. A server identity on a Kavita source is
     * Kavita's; so is one whose source is gone but whose id is a Kavita chapter; so is a kept
     * download, which has a local identity and a remembered origin.
     */
    fun ownedByKavita(identity: PublicationIdentity): Boolean {
        identity.serverIdentifier?.let { server ->
            val source = sources.sources.firstOrNull { it.id == server.sourceId }
            if (source?.kind == SourceKind.KAVITA_SERVER) return true
            if (source == null && server.remoteId.startsWith(KAVITA_CHAPTER)) return true
        }
        return identity.stableId in kavitaKept
    }

    private companion object {
        const val KAVITA_CHAPTER = "chapter:"
    }
}

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
     * @param secrets the sealed credentials, when the reader chose to carry them. Sealed by
     *   [LibrarySecretSealer]; null is what the writer does unless it was asked.
     */
    fun document(
        snapshot: LibrarySnapshot,
        appVersion: String,
        writtenAtEpochMillis: Long,
        secrets: LibrarySecrets? = null,
    ): LibraryDocument = LibraryDocument(
        appVersion = appVersion,
        writtenBy = LibraryDocument.THIS_PLATFORM,
        writtenAt = wireMoment(writtenAtEpochMillis),
        library = body(snapshot, device = null, previous = null),
        secrets = secrets,
    )

    /**
     * What a sync writes: the export, with no Kavita position and with the device beside each
     * moment.
     *
     * `library-sync` tasks 3.1 and 3.7. It never carries secrets.
     *
     * @param device this install's id. See [LibrarySyncState].
     * @param previous the document this write replaces. A moment it already carried keeps the
     *   device it named, because this device only took that change.
     */
    fun syncDocument(
        snapshot: LibrarySnapshot,
        appVersion: String,
        writtenAtEpochMillis: Long,
        device: String,
        previous: LibraryDocument?,
    ): LibraryDocument {
        val owned = snapshot.copy(progress = snapshot.progress.filterNot { snapshot.ownedByKavita(it.identity) })
        return LibraryDocument(
            appVersion = appVersion,
            writtenBy = LibraryDocument.THIS_PLATFORM,
            writtenAt = wireMoment(writtenAtEpochMillis),
            library = body(owned, device, previous?.library),
        )
    }

    /**
     * Only a server's shelf is a shelf the server owns, and a server's shelves are fetched
     * rather than remembered — so nothing local is exported for them, the same rule
     * `ShelvesStore` already writes to disk by.
     */
    private fun body(snapshot: LibrarySnapshot, device: String?, previous: LibraryBody?) = LibraryBody(
        sources = snapshot.sources.sources.map(::documentSource),
        certificatePins = snapshot.certificatePins.mapValues { it.value.sorted() },
        collections = snapshot.shelves.collections
            .filter { it.origin == ShelfOrigin.Local }
            .map {
                val before = previous?.collections?.firstOrNull { old -> old.id.sameId(it.id) }
                DocumentCollection(
                    id = it.id.toString(),
                    name = it.name,
                    // Sorted for the reason `ShelvesStore` sorts: a set has no order, and two
                    // exports of one library should not differ.
                    members = it.members.sorted(),
                    coverMemberId = it.coverMemberId,
                    changedAt = it.changedAtEpochMillis.takeIf { at -> at > 0 }?.let(::wireMoment),
                    changedBy = changedBy(it.changedAtEpochMillis, before?.changedAt, before?.changedBy, device),
                )
            },
        readingLists = snapshot.shelves.lists
            .filter { it.origin == ShelfOrigin.Local }
            .map {
                val before = previous?.readingLists?.firstOrNull { old -> old.id.sameId(it.id) }
                DocumentReadingList(
                    id = it.id.toString(),
                    name = it.name,
                    entries = it.entries,
                    coverMemberId = it.coverMemberId,
                    changedAt = it.changedAtEpochMillis.takeIf { at -> at > 0 }?.let(::wireMoment),
                    changedBy = changedBy(it.changedAtEpochMillis, before?.changedAt, before?.changedBy, device),
                )
            },
        pinnedShelves = snapshot.pinnedShelves.tokens,
        settings = DocumentSettings(snapshot.settings).copy(
            changed = ChangeStamps.documentStamps(
                snapshot.settingsChangedAt, previous?.settings?.changed.orEmpty(), device,
            ),
        ),
        readingThemes = DocumentThemes(
            entries = snapshot.themes.entries.map {
                DocumentThemeEntry(
                    scope = it.scope.name.toWireCase(),
                    shelf = it.shelf,
                    settings = DocumentShelfSettings(it.settings),
                )
            },
            customPalette = snapshot.themes.customPalette,
            changed = ChangeStamps.documentStamps(
                snapshot.themesChangedAt, previous?.readingThemes?.changed.orEmpty(), device,
            ),
        ),
        progress = snapshot.progress.map {
            val identity = DocumentIdentity(it.identity)
            val before = previous?.progress?.firstOrNull { old -> old.identity == identity }
            DocumentProgress(
                identity = identity,
                position = DocumentPosition(it.position),
                isFinished = it.isFinished,
                finishedAt = it.finishedAtEpochMillis?.let(::wireMoment),
                updatedAt = wireMoment(it.updatedAtEpochMillis),
                changedBy = ChangeStamps.by(it.updatedAtEpochMillis, before?.updatedAt, before?.changedBy, device),
            )
        },
        // Sorted for the reason collections are: two exports of one library should not differ.
        covers = snapshot.covers.sortedBy { it.key }.map {
            DocumentCover(it.key, Base64.getEncoder().encodeToString(it.image))
        },
        removedShelves = snapshot.removedShelves.sortedBy { it.id }.map {
            val before = previous?.removedShelves?.firstOrNull { old -> old.id.sameId(it.id) }
            DocumentTombstone(
                id = it.id.toString(),
                removedAt = wireMoment(it.removedAtEpochMillis),
                removedBy = ChangeStamps.by(it.removedAtEpochMillis, before?.removedAt, before?.removedBy, device),
            )
        },
    )

    /** A shelf's device: none for a shelf from before sync, which has no moment either. */
    private fun changedBy(at: Long, previousAt: String?, previousBy: String?, device: String?): String? =
        if (at > 0) ChangeStamps.by(at, previousAt, previousBy, device) else null

    private fun String.sameId(id: java.util.UUID): Boolean = LibraryImport.wireId(this) == id

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
