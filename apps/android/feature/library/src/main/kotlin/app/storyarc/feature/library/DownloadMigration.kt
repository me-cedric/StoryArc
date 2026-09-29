package app.storyarc.feature.library

import app.storyarc.core.catalogue.OpdsOrigin
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadLibrary
import java.util.UUID

/**
 * Fixes an OPDS download recorded before source-keyed ids existed.
 *
 * `offline-downloads` dl-core 1.2: a download queued before this fix carries the bare
 * catalogue entry id and no source, so a second catalogue that numbers its entries the same
 * way shares its record and its file. Nothing can recover a source for a stray record in
 * general -- the source was never written down -- but the queue for one catalogue knows its
 * own origin, and a stray record whose remote address belongs to that origin can only be
 * that catalogue's. Migrating there, rather than in one pass over every source, needs no
 * registry and touches only the strays a queue is actually about to reuse -- which is also
 * every stray this app will ever open again. iOS's `DownloadMigration` is the same fix.
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
