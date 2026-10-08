package app.storyarc.core.persistence

import android.content.Context
import app.storyarc.core.model.ChosenCover
import app.storyarc.core.model.ChosenCoverStore
import app.storyarc.core.model.LibrarySnapshot
import app.storyarc.core.model.PinnedShelves
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.ShelfPin
import app.storyarc.core.model.coverOverrideKey
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

/**
 * The seven stores a [LibrarySnapshot] is made of, read together and written together, and the
 * cover store when one is handed in.
 *
 * `library-portability` names what an export carries, and what it names is spread across six
 * preference files and one Room database. This is the only place that knows which store holds
 * which part, so `LibraryExport` and `LibraryImport` can stay pure and be asserted without a
 * disk.
 *
 * iOS's `LibraryArchive` reads and writes the same seven.
 */
class LibraryArchive(
    private val sources: SourceStore,
    private val certificatePins: CertificatePinStore,
    private val shelves: ShelvesStore,
    private val library: LibraryPreferences,
    private val settings: SettingsStore,
    private val reader: ReaderPreferences,
    private val progress: ProgressLedger,
    /** Which publications Kavita owns. An archive built without it marks none. */
    private val kavita: KavitaProgressStore? = null,
    /**
     * Where chosen covers are kept. `:core:persistence` cannot see `:core:format`, so the app
     * hands the store in; an archive built without one neither reads nor writes covers.
     */
    private val covers: ChosenCoverStore? = null,
) {
    /** The failure an import reports when a cover could not be written. */
    class CoverNotWritten(val key: String) : Exception("cover not written: $key")

    companion object {
        fun open(context: Context, covers: ChosenCoverStore? = null): LibraryArchive = LibraryArchive(
            sources = SourceStore.open(context),
            certificatePins = CertificatePinStore.open(context),
            shelves = ShelvesStore.open(context),
            library = LibraryPreferences.open(context),
            settings = SettingsStore.open(context),
            reader = ReaderPreferences.open(context),
            progress = ProgressStore.open(context),
            kavita = KavitaProgressStore.open(context),
            covers = covers,
        )
    }

    /** Everything the export carries, as it stands right now. */
    suspend fun snapshot(): LibrarySnapshot {
        val library = held()
        return library.copy(covers = covers?.chosen(coverKeys(library)).orEmpty())
    }

    /**
     * Every key a cover could be filed under for what the library holds, for the covers a store
     * has no key file for.
     */
    private fun coverKeys(library: LibrarySnapshot): Set<String> =
        library.progress.map { it.identity.coverOverrideKey }.toSet() +
            library.shelves.collections.flatMap { it.members } +
            library.shelves.lists.flatMap { it.entries }

    private suspend fun held(): LibrarySnapshot = LibrarySnapshot(
        sources = sources.registry(),
        certificatePins = certificatePins.pins(),
        shelves = shelves.shelves(),
        pinnedShelves = PinnedShelves(
            library.pinnedShelves().mapNotNull(ShelfPin::of).toSet(),
        ),
        settings = settings.settings(),
        themes = reader.themes(),
        // Everything, not a page of it. `recent(limit:)` is the only enumeration this store
        // has, and the export wants every record rather than the ones a "Continue reading"
        // row would show.
        progress = progress.recent(limit = Int.MAX_VALUE),
        removedShelves = shelves.removed(),
        settingsChangedAt = settings.changedAt(),
        themesChangedAt = reader.themesChangedAt(),
        kavitaKept = kavita?.rememberedPublications().orEmpty(),
    )

    /**
     * Writes a merged snapshot back, all or nothing.
     *
     * `library-portability` / *Import merges*: a throw part-way leaves the device as it was.
     * The device is read first. On a failure the six small stores are written back from that
     * reading and the progress records are put back one by one, and then the failure is
     * thrown again. An import that stopped after the third store would otherwise leave a
     * library that is neither the old one nor the new one, and nothing to say so.
     *
     * @param exactly true for a sync, whose merge already decided each moment and deletion. A
     *   store that stamped them again would date a member the merge took as a change made now.
     */
    suspend fun apply(merged: LibrarySnapshot, exactly: Boolean = false) {
        val before = snapshot()
        val replacedCovers = mutableListOf<Pair<String, ByteArray?>>()
        try {
            writeCovers(merged.covers, replacedCovers)
            writeStores(merged, exactly)
            writeProgress(merged.progress)
        } catch (failure: Exception) {
            // Undone even when the import was cancelled, or the cancel would be the half import.
            withContext(NonCancellable) {
                restoreCovers(replacedCovers)
                writeStores(before, exactly = true)
                // The failure the reader needs is the first one. A second one while undoing
                // cannot be shown better than that, so it does not replace it.
                runCatching { restoreProgress(before.progress, over = merged.progress) }
            }
            throw failure
        }
    }

    /** Each cover the device does not hold already, with what it replaced noted for the undo. */
    private fun writeCovers(
        chosen: List<ChosenCover>,
        replaced: MutableList<Pair<String, ByteArray?>>,
    ) {
        val store = covers ?: return
        for (cover in chosen) {
            val previous = store.image(cover.key)
            if (previous != null && previous.contentEquals(cover.image)) continue
            if (!store.store(cover.key, cover.image)) throw CoverNotWritten(cover.key)
            replaced += cover.key to previous
        }
    }

    private fun restoreCovers(replaced: List<Pair<String, ByteArray?>>) {
        val store = covers ?: return
        for ((key, previous) in replaced) {
            if (previous != null) store.store(key, previous) else store.remove(key)
        }
    }

    /**
     * @param exactly true for an undo or a sync, which write the moments and deletions as given.
     *   Otherwise a store stamps what changed and records what was deleted.
     */
    private fun writeStores(snapshot: LibrarySnapshot, exactly: Boolean = false) {
        sources.save(snapshot.sources)
        certificatePins.save(snapshot.certificatePins)
        library.savePinnedShelves(snapshot.pinnedShelves.tokens)
        if (exactly) {
            shelves.restore(snapshot.shelves, snapshot.removedShelves)
            settings.restore(snapshot.settings, snapshot.settingsChangedAt)
            reader.restore(snapshot.themes, snapshot.themesChangedAt)
        } else {
            shelves.save(snapshot.shelves, snapshot.removedShelves)
            settings.save(snapshot.settings, snapshot.settingsChangedAt)
            reader.save(snapshot.themes, snapshot.themesChangedAt)
        }
    }

    /**
     * Reading progress goes through [ProgressLedger.save] one record at a time rather than
     * being written wholesale, because that method is where finished stays sticky — a bulk
     * write that bypassed it could unmark a publication the merge had just decided was
     * finished.
     */
    private suspend fun writeProgress(records: List<ReadingProgress>) {
        for (record in records) {
            progress.save(record)
            if (record.isFinished) {
                progress.mark(record.identity, isFinished = true, at = record.updatedAtEpochMillis)
            }
        }
    }

    /**
     * Puts every record the import may have touched back as [before] held it.
     *
     * A record [before] did not hold is forgotten. One it held is saved again, and then marked
     * unfinished when it was unfinished: [ProgressLedger.save] keeps finished sticky, so saving
     * alone would leave the flag the import turned on.
     */
    private suspend fun restoreProgress(before: List<ReadingProgress>, over: List<ReadingProgress>) {
        for (record in over) {
            val prior = before.firstOrNull { it.identity.matches(record.identity) }
            if (prior == null) {
                progress.forget(record.identity)
            } else {
                progress.save(prior)
                if (!prior.isFinished) {
                    progress.mark(prior.identity, isFinished = false, at = prior.updatedAtEpochMillis)
                }
            }
        }
    }
}
