package app.storyarc.feature.library

import app.storyarc.core.format.FilenameMetadata
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.smb.SmbAddress
import app.storyarc.core.smb.SmbClient
import app.storyarc.core.smb.SmbEntry
import java.util.UUID

/**
 * What a network share puts in the library.
 *
 * `library-browsing` requires one library over every source, and a share was reachable only
 * by browsing to it. Unlike a server, a share cannot be *asked* — it is a filesystem, and a
 * filesystem is walked. That is the whole difficulty, and it is why this was the last of the
 * three to be written.
 *
 * **A bounded walk, breadth-first.** A share may hold a hundred thousand files across a
 * thousand folders, and a blind walk of one over a network is minutes of round trips that
 * nobody asked for. This lists the root, then the folders it found, level by level, and
 * stops at [FIRST_SLICE] publications or [MAX_FOLDERS] listings, whichever comes first.
 * Breadth-first rather than depth-first on purpose: shares put their folders at the root, so
 * a depth-first walk would spend the whole budget inside the first one.
 *
 * What the walk did not reach stays reachable through the browser and through search, which
 * is what *More from a source than the library holds* already requires.
 *
 * **The metadata is the filename's, and says so.** Reading a publication's own metadata
 * means fetching the archive, and this walk is deliberately not doing that: fifty archives
 * pulled over a network to fill a shelf is the cost this bound exists to avoid.
 * [MetadataOrigin.INFERRED] is what the row carries, so a later read of the file itself
 * outranks it -- `LibraryMerge` keeps a downloaded file's own answer over a guess.
 */
internal object SmbContributor {

    /** How many publications one read of a share takes. */
    const val FIRST_SLICE = 200

    /** How many directory listings it will spend to find them. */
    const val MAX_FOLDERS = 40

    /** The publications a bounded walk of the share finds. */
    suspend fun publications(sourceId: UUID, client: SmbClient, address: SmbAddress): SourceSlice {
        val found = mutableListOf<Publication>()
        val queue = ArrayDeque(listOf(address.path))
        var listings = 0

        while (queue.isNotEmpty() && found.size < FIRST_SLICE && listings < MAX_FOLDERS) {
            val path = queue.removeFirst()
            // A folder that refuses is skipped, not fatal: one unreadable directory must
            // not cost a reader the rest of the share.
            val entries = runCatching { client.list(path) }.getOrNull() ?: continue
            listings += 1
            for (entry in entries) {
                if (entry.isDirectory) {
                    queue.addLast(entry.path)
                    continue
                }
                if (found.size >= FIRST_SLICE) break
                publication(sourceId, entry, address, folder = path)?.let(found::add)
            }
        }
        // Either budget running out is the walk stopping before the share did, and so is a
        // queue with folders still in it. All three mean the same thing to a reader: there
        // is more on the share than the number on the screen.
        return SourceSlice(
            publications = found,
            holdsMore = queue.isNotEmpty() || found.size >= FIRST_SLICE || listings >= MAX_FOLDERS,
        )
    }

    /**
     * One file as a row, or null for a file this app cannot open.
     *
     * The identity is the share's own `smb://` address for this file, not the bare path
     * `SmbClient.list` returns: `entry.path` is relative to the share's root, and a location
     * that is not a real address reads as local — `PublicationAccess.isRemote` matches it
     * against nothing, the shelf counts a row nobody has downloaded as already on the
     * device, and opening it hands the reader a path that exists nowhere on the filesystem.
     * [SmbLocator.entry] is the same address the share browser opens a file by, and the one
     * the reader's opener reads back with [SmbLocator.inside].
     *
     * Still one identity per file on the share: two rows are the same publication when
     * they are the same file, and a share's row and the same file downloaded fold together
     * without a server identifier, which is `PublicationIdentity.matches` doing what
     * ADR-0006 built it for.
     */
    internal fun publication(
        sourceId: UUID,
        entry: SmbEntry,
        address: SmbAddress,
        folder: String,
    ): Publication? {
        val format = format(entry.name) ?: return null
        val facts = FilenameMetadata.of(entry.name, seriesHint = folder.substringAfterLast('/'))
        return Publication(
            identity = PublicationIdentity(normalizedPath = SmbLocator.entry(entry.path, address)),
            format = format,
            // The filename without its extension. `FilenameMetadata` answers series,
            // number, volume and year and deliberately not a title -- what is left of a
            // name once those are taken out is not reliably one.
            displayTitle = entry.name.substringBeforeLast('.', entry.name),
            series = facts.series,
            number = facts.number,
            volume = facts.volume,
            year = facts.year,
            // The filename's, and not the file's: reading the file means fetching it.
            origin = MetadataOrigin.INFERRED,
            sourceId = sourceId,
            // The share already states this for free -- a directory entry carries its
            // own length -- so the download offer on the publication page can state a
            // size instead of leaving the reader guessing.
            fileSize = entry.length,
        )
    }

    /** The format a name declares, or null for a file that is not a publication. */
    private fun format(name: String): PublicationFormat? =
        when (name.substringAfterLast('.', "").lowercase()) {
            "cbz" -> PublicationFormat.CBZ
            "cbr" -> PublicationFormat.CBR
            "cb7" -> PublicationFormat.CB7
            "cbt" -> PublicationFormat.CBT
            "epub" -> PublicationFormat.EPUB
            "pdf" -> PublicationFormat.PDF
            else -> null
        }
}
