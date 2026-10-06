package app.storyarc.core.persistence

import android.content.Context
import app.storyarc.core.model.LibrarySnapshot
import app.storyarc.core.model.PinnedShelves
import app.storyarc.core.model.ShelfPin

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
    private val progress: ProgressStore,
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
     * Writes a merged snapshot back, store by store.
     *
     * Reading progress goes through [ProgressStore.save] one record at a time rather than
     * being written wholesale, because that method is where finished stays sticky — a bulk
     * write that bypassed it could unmark a publication the merge had just decided was
     * finished.
     */
    suspend fun apply(snapshot: LibrarySnapshot) {
        sources.save(snapshot.sources)
        certificatePins.save(snapshot.certificatePins)
        shelves.save(snapshot.shelves)
        library.savePinnedShelves(snapshot.pinnedShelves.tokens)
        settings.save(snapshot.settings)
        reader.save(snapshot.themes)
        for (record in snapshot.progress) {
            progress.save(record)
            if (record.isFinished) {
                progress.mark(record.identity, isFinished = true, at = record.updatedAtEpochMillis)
            }
        }
    }
}
