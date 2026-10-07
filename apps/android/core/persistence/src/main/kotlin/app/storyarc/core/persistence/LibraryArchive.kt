package app.storyarc.core.persistence

import android.content.Context
import app.storyarc.core.model.LibrarySnapshot
import app.storyarc.core.model.PinnedShelves
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.ShelfPin
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

/**
 * The seven stores a [LibrarySnapshot] is made of, read together and written together.
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
) {
    companion object {
        fun open(context: Context): LibraryArchive = LibraryArchive(
            sources = SourceStore.open(context),
            certificatePins = CertificatePinStore.open(context),
            shelves = ShelvesStore.open(context),
            library = LibraryPreferences.open(context),
            settings = SettingsStore.open(context),
            reader = ReaderPreferences.open(context),
            progress = ProgressStore.open(context),
        )
    }

    /** Everything the export carries, as it stands right now. */
    suspend fun snapshot(): LibrarySnapshot = LibrarySnapshot(
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
    )

    /**
     * Writes a merged snapshot back, all or nothing.
     *
     * `library-portability` / *Import merges*: a throw part-way leaves the device as it was.
     * The device is read first. On a failure the six small stores are written back from that
     * reading and the progress records are put back one by one, and then the failure is
     * thrown again. An import that stopped after the third store would otherwise leave a
     * library that is neither the old one nor the new one, and nothing to say so.
     */
    suspend fun apply(merged: LibrarySnapshot) {
        val before = snapshot()
        try {
            writeStores(merged)
            writeProgress(merged.progress)
        } catch (failure: Exception) {
            // Undone even when the import was cancelled, or the cancel would be the half import.
            withContext(NonCancellable) {
                writeStores(before)
                // The failure the reader needs is the first one. A second one while undoing
                // cannot be shown better than that, so it does not replace it.
                runCatching { restoreProgress(before.progress, over = merged.progress) }
            }
            throw failure
        }
    }

    private fun writeStores(snapshot: LibrarySnapshot) {
        sources.save(snapshot.sources)
        certificatePins.save(snapshot.certificatePins)
        shelves.save(snapshot.shelves)
        library.savePinnedShelves(snapshot.pinnedShelves.tokens)
        settings.save(snapshot.settings)
        reader.save(snapshot.themes)
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
