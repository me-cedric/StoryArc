package app.storyarc.feature.library

import app.storyarc.core.catalogue.OpdsOrigin
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.DownloadStore
import java.util.UUID

/**
 * Fixes an OPDS download recorded before source-keyed ids existed.
 *
 * `offline-downloads` dl-core 1.2: a download queued before this fix carries the bare
 * catalogue entry id and no source, so a second catalogue that numbers its entries the same
 * way shares its record and its file. Nothing can recover a source for a stray record in
 * general -- the source was never written down -- but each catalogue knows its own origin,
 * and a stray record whose remote address belongs to that origin can only be that
 * catalogue's. The app-level queue runs this pass for every catalogue before it reads the
 * store -- see [migratingOpdsStrays]. iOS's `DownloadMigration` is the same fix.
 */
internal object DownloadMigration {

    /** What one migration pass produced: the fixed library, and which directories moved. */
    data class Result(val library: DownloadLibrary, val renamed: List<Pair<String, String>>)

    /**
     * Re-keys every stray this origin owns, and says which directories moved so the store
     * can rename them on disk.
     *
     * A record already carrying a source is left alone -- it was written by this fix, by
     * Kavita, or by a local keep, all of which already attribute correctly -- so a repeat
     * call on every launch does nothing once every stray this origin owns has been found.
     */
    fun migrating(library: DownloadLibrary, sourceId: UUID, origin: OpdsOrigin): Result {
        val renamed = mutableListOf<Pair<String, String>>()
        val migrated = library.downloads.map { download ->
            if (download.sourceId != null || OpdsOrigin.of(download.remote) != origin) {
                download
            } else {
                val newId = "opds:$sourceId:${download.id}"
                renamed += download.id to newId
                download.copy(id = newId, sourceId = sourceId)
            }
        }
        if (renamed.isEmpty()) return Result(library, emptyList())
        return Result(DownloadLibrary(migrated), renamed)
    }
}

/**
 * Re-keys every stray that a registered catalogue owns, before the app-level queue reads this
 * store.
 *
 * The one app-level queue (dl-core 1.1) has no origin of its own, so it cannot run
 * [DownloadMigration.migrating] for itself. This runs that pass once for each OPDS catalogue.
 * When two catalogues share an origin, the first one in the registry takes the stray.
 */
fun DownloadStore.migratingOpdsStrays(sources: List<Source>) {
    var library = library()
    val renamed = mutableListOf<Pair<String, String>>()
    for (source in sources) {
        if (source.kind != SourceKind.OPDS_CATALOG) continue
        val origin = source.locator?.let(OpdsOrigin::of) ?: continue
        val step = DownloadMigration.migrating(library, source.id, origin)
        library = step.library
        renamed += step.renamed
    }
    if (renamed.isEmpty()) return
    renamed.forEach { (from, to) -> rename(from, to) }
    save(library)
}
