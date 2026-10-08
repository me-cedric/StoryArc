package app.storyarc.core.model

import java.net.URI
import java.util.Base64
import java.util.UUID

/**
 * A document merged into what the device already holds.
 *
 * `library-portability` / *Import merges*: the app "merges an import into what the device
 * already holds, record by record", and does not replace the library wholesale. A reader
 * importing onto a device they have been using would lose that device's reading with a
 * replace, and would not be told which.
 *
 * Pure, over a [LibrarySnapshot], so the rules can be asserted without a store. iOS's
 * `LibraryImport` applies the same rules in the same order.
 */
object LibraryImport {

    /**
     * The identifier a wire record carries, parsed, or null where it is not an identifier.
     *
     * Every comparison below reads this rather than the text. Swift renders a `UUID` in upper
     * case and Java renders one in lower case, so a document an iPhone wrote names each
     * source, collection and list in a spelling this device never matches. Compared as text,
     * a source the reader already holds reads as a new one, and they are asked to sign in
     * again to a server they are already signed in to.
     */
    internal fun wireId(id: String): UUID? = runCatching { UUID.fromString(id) }.getOrNull()

    /** What an import would do, with nothing changed. */
    fun plan(document: LibraryDocument, device: LibrarySnapshot): LibraryImportPlan {
        val held = device.sources.sources.map { it.id }.toSet()
        val arriving = document.library.sources.filterNot { wireId(it.id) in held }

        val heldCollections = device.shelves.collections.associateBy { it.id }
        val heldLists = device.shelves.lists.associateBy { it.id }

        val shelvesToAdd = mutableListOf<String>()
        val shelvesToMerge = mutableListOf<ImportedShelf>()
        for (collection in document.library.collections) {
            val mine = heldCollections[wireId(collection.id)]
            if (mine == null) {
                shelvesToAdd += collection.name
            } else {
                val added = (collection.members.toSet() - mine.members).size
                shelvesToMerge += ImportedShelf(mine.name, added)
            }
        }
        for (list in document.library.readingLists) {
            val mine = heldLists[wireId(list.id)]
            if (mine == null) {
                shelvesToAdd += list.name
            } else {
                shelvesToMerge += ImportedShelf(
                    mine.name,
                    list.entries.count { it !in mine.entries },
                )
            }
        }

        val arrivingProgress = readableProgress(document)
            .partition { heldProgress(it.identity, device) == null }

        val heldThemes = device.themes.entries.map(::themeKey).toSet()
        val arrivingThemes = document.library.readingThemes.entries
            .filterNot { "${it.scope}/${it.shelf.orEmpty()}" in heldThemes }

        return LibraryImportPlan(
            sourcesToAdd = arriving.map { it.displayName },
            sourcesNeedingSignIn = signInsNeeded(document, device),
            shelvesToAdd = shelvesToAdd,
            shelvesToMerge = shelvesToMerge,
            progressToAdd = arrivingProgress.first.size,
            progressToMerge = arrivingProgress.second.size,
            certificatePinsToAdd = pinsArriving(document, device),
            settingsWillChange = document.library.settings.settings(device.settings) != device.settings,
            themeEntriesToAdd = arrivingThemes.size,
            coversToAdd = coversArriving(document, device).size,
        )
    }

    /** The device as the import leaves it, with whatever the merge had to tell the reader. */
    fun merging(document: LibraryDocument, device: LibrarySnapshot): LibraryImportResult {
        val progress = mergingProgress(document, device)
        return LibraryImportResult(
            snapshot = device.copy(
                sources = mergingSources(document, device.sources),
                certificatePins = mergingPins(document, device.certificatePins),
                shelves = mergingShelves(document, device.shelves),
                pinnedShelves = PinnedShelves(
                    (device.pinnedShelves.tokens + document.library.pinnedShelves)
                        .mapNotNull(ShelfPin::of)
                        .toSet(),
                ),
                // The document's settings win where they differ, because a reader importing
                // their library is asking for the device to look like the one they left. A
                // merge would have to decide per field, and there is no honest rule for
                // "which of two appearances did they mean" — unlike a reading position,
                // where "furthest" is one.
                settings = document.library.settings.settings(device.settings),
                themes = mergingThemes(document, device.themes),
                progress = progress.first,
                covers = device.covers + coversArriving(document, device),
            ),
            conflicts = progress.second,
            sourcesNeedingSignIn = signInsNeeded(document, device),
        )
    }

    // Sources.

    /**
     * A source the device already has is left alone.
     *
     * Its state, its secure-store handle and whatever it has learned since belong to this
     * device. Overwriting a working source with a stale copy of itself would log the reader
     * out of a server they are signed in to, which is the one thing an import must not do.
     */
    private fun mergingSources(document: LibraryDocument, registry: SourceRegistry):
        SourceRegistry {
        val held = registry.sources.map { it.id }.toSet()
        return document.library.sources
            .filterNot { wireId(it.id) in held }
            .fold(registry) { carried, arriving ->
                val id = wireId(arriving.id)
                // A kind this build does not know is dropped rather than guessed at, the same
                // rule `SourceStore` already reads its own disk by.
                val kind = wireEnumOrNull<SourceKind>(arriving.kind)
                if (id == null || kind == null) {
                    carried
                } else {
                    carried.adding(
                        Source(
                            id = id,
                            displayName = arriving.displayName,
                            kind = kind,
                            lastSuccessfulSyncEpochMillis = epochMillis(arriving.lastSuccessfulSync),
                            credentialReference = null,
                            locator = arriving.locator,
                        ),
                    )
                }
            }
    }

    /**
     * Every source the reader will have to sign in to again, by name.
     *
     * A source whose secret this device already holds is not one of them, even when the
     * document says it needed one: the secret the reader is being asked for is the one that
     * is missing *here*.
     */
    internal fun signInsNeeded(
        document: LibraryDocument,
        device: LibrarySnapshot,
        credentialed: Set<UUID> = emptySet(),
    ): List<String> {
        val signedIn = device.sources.sources
            .filter { it.credentialReference != null }
            .map { it.id }
            .toSet() + credentialed
        return document.library.sources
            .filter { it.needsSignIn && wireId(it.id) !in signedIn }
            .map { it.displayName }
    }

    // Certificate pins.

    private fun pinsArriving(document: LibraryDocument, device: LibrarySnapshot):
        List<CertificatePinNotice> = document.library.certificatePins
        .mapNotNull { (host, fingerprints) ->
            val held = device.certificatePins[host].orEmpty()
            if ((fingerprints.toSet() - held).isEmpty()) {
                null
            } else {
                CertificatePinNotice(host, sourceNaming(host, document))
            }
        }
        .sortedBy { it.host }

    /**
     * The source in the document whose address points at this host.
     *
     * The host is parsed out of the address rather than searched for inside it. `nas.local`
     * is a substring of `evil-nas.local`, so a search names whichever source sorts first and
     * can put a trusted name beside a stranger's fingerprint -- on the one notice that asks
     * the reader to accept it.
     */
    private fun sourceNaming(host: String, document: LibraryDocument): String? =
        document.library.sources.firstOrNull { hostOf(it.locator) == host }?.displayName

    /** The host an address names, or null where it names none. */
    private fun hostOf(locator: String?): String? =
        locator?.let { runCatching { URI(it).host }.getOrNull() }

    private fun mergingPins(document: LibraryDocument, held: Map<String, Set<String>>):
        Map<String, Set<String>> = document.library.certificatePins
        .entries
        .fold(held) { carried, (host, fingerprints) ->
            carried + (host to carried[host].orEmpty() + fingerprints)
        }

    // Shelves.

    private fun mergingShelves(document: LibraryDocument, shelves: Shelves): Shelves {
        var merged = shelves
        for (arriving in document.library.collections) {
            val id = wireId(arriving.id) ?: continue
            val mine = merged.collections.firstOrNull { it.id == id }
            if (mine == null) {
                merged = merged.adding(
                    PublicationCollection(
                        id = id,
                        name = arriving.name,
                        members = arriving.members.toSet(),
                        coverMemberId = arriving.coverMemberId,
                    ),
                )
                continue
            }
            merged = merged.adding(arriving.members.toSet(), to = id)
            // The device's own chosen cover stands; the document's fills a choice never made.
            if (mine.coverMemberId == null && arriving.coverMemberId != null) {
                merged = merged.settingCover(arriving.coverMemberId, on = id)
            }
        }
        for (arriving in document.library.readingLists) {
            val id = wireId(arriving.id) ?: continue
            val mine = merged.lists.firstOrNull { it.id == id }
            if (mine == null) {
                merged = merged.adding(
                    ReadingList(
                        id = id,
                        name = arriving.name,
                        entries = arriving.entries,
                        coverMemberId = arriving.coverMemberId,
                    ),
                )
                continue
            }
            // Appended rather than interleaved. A reading list's order is the reader's, and
            // there is no rule that can merge two orders without inventing one — so this
            // device's order is kept and whatever it did not have goes on the end.
            merged = merged.appending(arriving.entries.filterNot { it in mine.entries }, to = id)
            if (mine.coverMemberId == null && arriving.coverMemberId != null) {
                merged = merged.settingListCover(arriving.coverMemberId, onList = id)
            }
        }
        return merged
    }

    // Themes.

    /**
     * A choice the device has already made stands.
     *
     * The device is the one the reader is holding, and a theme they set on it this morning
     * should not be undone by a file written last week. What the device has never chosen is
     * taken from the document, which is the whole point of carrying them.
     */
    private fun mergingThemes(document: LibraryDocument, memory: ShelfMemory): ShelfMemory {
        val held = memory.entries.map(::themeKey).toSet()
        var merged = memory
        for (arriving in document.library.readingThemes.entries) {
            val scope = wireEnumOrNull<ThemeScope>(arriving.scope) ?: continue
            if ("${arriving.scope}/${arriving.shelf.orEmpty()}" in held) continue
            merged = merged.recording(
                ShelfMemory.Entry(scope, arriving.shelf, arriving.settings.settings()),
            )
        }
        return if (merged.customPalette == null) {
            merged.copy(customPalette = document.library.readingThemes.customPalette)
        } else {
            merged
        }
    }

    private fun themeKey(entry: ShelfMemory.Entry): String =
        "${entry.scope.name.toWireCase()}/${entry.shelf.orEmpty()}"

    // Covers.

    /**
     * The largest image an import accepts, decoded. A cover is shaped to a few hundred
     * kilobytes, so this is a ceiling for a document that is not an export of this app. iOS's
     * `LibraryImport.maximumCoverBytes` holds the same number.
     */
    const val MAXIMUM_COVER_BYTES = 8 * 1024 * 1024

    /**
     * The covers the merge will write: readable, within the ceiling, and not chosen already.
     *
     * A cover the device holds under the same key stands, for the reason a theme the device
     * chose stands: it is the one the reader is holding. The one decode step the preview and
     * the merge share, so the count the reader is shown is the count that lands.
     */
    private fun coversArriving(document: LibraryDocument, device: LibrarySnapshot): List<ChosenCover> {
        val seen = device.covers.map { it.key }.toMutableSet()
        return document.library.covers.mapNotNull { cover ->
            val image = runCatching { Base64.getDecoder().decode(cover.image) }.getOrNull()
            if (image == null || image.isEmpty() || image.size > MAXIMUM_COVER_BYTES ||
                !seen.add(cover.key)
            ) {
                null
            } else {
                ChosenCover(cover.key, image)
            }
        }
    }

    // Progress.

    /**
     * Reading progress through the machinery a server disagreement already goes through.
     *
     * ADR-0006's rules, unchanged: the furthest position wins and finished is sticky. An
     * import is the same problem as a server disagreement, so [ProgressPull.merging] decides
     * it rather than a second rule that could drift from the first.
     *
     * The document carries no watermark — see [DocumentProgress] — so every arriving record
     * meets a local one that may have none either. That is the case task 1.4 fixed, and this
     * function is why it had to be fixed first.
     */
    private fun mergingProgress(document: LibraryDocument, device: LibrarySnapshot):
        Pair<List<ReadingProgress>, List<ProgressPull.Conflict>> {
        val arriving = readableProgress(document)
        val pull = ProgressPull.merging(arriving) { identity -> heldProgress(identity, device) }

        val merged = device.progress.toMutableList()
        for (record in pull.toSave) {
            val existing = merged.indexOfFirst { it.identity.matches(record.identity) }
            if (existing >= 0) merged[existing] = record else merged += record
        }
        return merged to pull.conflicts
    }

    /**
     * The records the merge will keep: the one decode step the preview and the merge share.
     *
     * A record whose position or whose update time this build cannot read is dropped here, so
     * the count the reader is shown is the count that lands. iOS's
     * `LibraryImport.readableProgress` is the same step, and drops the same records for an unreadable position.
     */
    private fun readableProgress(document: LibraryDocument): List<ReadingProgress> =
        document.library.progress.mapNotNull { record ->
            ReadingProgress(
                identity = record.identity.identity(),
                position = record.position.position() ?: return@mapNotNull null,
                isFinished = record.isFinished,
                finishedAtEpochMillis = epochMillis(record.finishedAt),
                updatedAtEpochMillis = epochMillis(record.updatedAt) ?: return@mapNotNull null,
            )
        }

    private fun heldProgress(identity: PublicationIdentity, device: LibrarySnapshot):
        ReadingProgress? = device.progress.firstOrNull { it.identity.matches(identity) }
}

/**
 * The device after an import, and what the merge had to tell the reader.
 *
 * [conflicts] are positions where both sides had moved. `reading-progress` shows these once,
 * naming both, with the option to take the other — the same notice a server disagreement
 * gets.
 */
data class LibraryImportResult(
    val snapshot: LibrarySnapshot,
    val conflicts: List<ProgressPull.Conflict>,
    /**
     * Sources that were given a secret by this import: their handle is set and the secret still
     * has to be written to the secure store.
     */
    val credentialed: Set<UUID> = emptySet(),
    /** Sources, by name, that the reader still has to sign in to. */
    val sourcesNeedingSignIn: List<String> = emptyList(),
)
