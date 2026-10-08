package app.storyarc.core.model

/** A file in a sync place, with the version the place gave it when it was read. */
data class SyncFile(val text: String, val version: String)

/**
 * Where the sync document lives: a share the reader added, or a folder they picked.
 *
 * `library-sync` tasks 2.2 and 2.3 fill this: an SMB write and a picked folder. The engine needs
 * no more than these four calls. Each call throws when the place cannot be reached, and the
 * caller shows the place as unreachable, not as an error.
 */
interface SyncPlace {
    /** The names of the files in the place, for the conflicted copies a provider leaves. */
    suspend fun names(): List<String>

    /** The file, or null when there is none. */
    suspend fun read(name: String): SyncFile?

    /**
     * Writes [text] only when the file is still at version [replacing], or still absent when
     * [replacing] is null. A place with an atomic replace uses it.
     *
     * @return false when the file changed since that read, with nothing written.
     */
    suspend fun write(name: String, text: String, replacing: String?): Boolean

    /** @return false when the file is still there. */
    suspend fun delete(name: String): Boolean
}

/** What one sync did. */
sealed interface LibrarySyncOutcome {
    /**
     * The device as the sync leaves it: the caller writes [merged]'s snapshot to the stores.
     *
     * @property skippedCopies conflicted copies that could not be read, by name. They stay in
     *   the place, and the reader is told.
     * @property mergedCopies conflicted copies merged and not deleted, as `name@version`. The
     *   caller keeps this set and hands it to the next sync, so no copy is merged twice.
     */
    data class Synced(
        val merged: LibrarySyncMerged,
        val skippedCopies: List<String> = emptyList(),
        val mergedCopies: Set<String> = emptySet(),
        /** The conflicted copies this sync merged, by name, so the reader can be told. */
        val copiesMergedNow: List<String> = emptyList(),
    ) : LibrarySyncOutcome

    /**
     * The document in the place cannot be read, by name: newer than this app, or not a library.
     * Nothing was written, so a newer app's document is never overwritten.
     */
    data class Refused(val reason: LibraryDocumentFailure) : LibrarySyncOutcome

    /** The document changed under every attempt. Nothing was written; the next sync tries again. */
    data object Busy : LibrarySyncOutcome
}

/**
 * Read, merge, write: one sync of the library document.
 *
 * `library-sync` task 3.1 / *Two devices write at once*: a write is never a blind overwrite.
 * The engine reads the document, merges it and any conflicted copy into this device, and writes
 * the result only when the document is still the one it read. When another device wrote in
 * between, it reads again and merges again, from this device's own state.
 *
 * iOS's `LibrarySync` is the same engine.
 *
 * @param device this install's id. See [LibrarySyncState].
 */
class LibrarySync(
    private val place: SyncPlace,
    private val device: String,
    private val appVersion: String,
    private val fileName: String = FILE_NAME,
    private val attempts: Int = ATTEMPTS,
) {
    companion object {
        /** The document's name in the place. iOS writes the same name. */
        const val FILE_NAME = "StoryArc Library.json"
        const val ATTEMPTS = 3

        /**
         * Whether [name] is a copy a file provider made of [of] when two devices wrote at once.
         *
         * Providers name one differently: `name 2.json` on iCloud Drive, `name (1).json` on
         * Google Drive, `name (… conflicted copy …).json` on Dropbox, `name-DEVICE.json` on
         * OneDrive. Each is the same name and extension with a suffix between them.
         */
        fun isConflictedCopy(name: String, of: String = FILE_NAME): Boolean {
            val base = of.substringBeforeLast('.')
            val extension = of.removePrefix(base)
            if (name == of || !name.startsWith(base) || !name.endsWith(extension)) return false
            if (name.length <= base.length + extension.length) return false
            val suffix = name.substring(base.length, name.length - extension.length)
            return COPY_SUFFIX.matches(suffix)
        }

        private val COPY_SUFFIX = Regex("""\s+\d+|\s*\(.+\)|-.+""")
    }

    private class Copy(val name: String, val key: String, val document: LibraryDocument)

    /**
     * @param mergedCopies what the last sync returned as [LibrarySyncOutcome.Synced.mergedCopies].
     */
    suspend fun sync(
        local: LibrarySnapshot,
        atEpochMillis: Long,
        mergedCopies: Set<String> = emptySet(),
    ): LibrarySyncOutcome {
        repeat(attempts) {
            val file = place.read(fileName)
            val document = file?.let { read ->
                LibraryDocumentCoder.decode(read.text).getOrElse { failure ->
                    return LibrarySyncOutcome.Refused(refusal(failure))
                }
            }
            val skipped = mutableListOf<String>()
            val copies = copies(mergedCopies, skipped)

            var merged = LibrarySyncMerged(local)
            // With no document yet, an empty one: the merge still settles each position this
            // device is about to write.
            val first = document ?: LibraryDocument(appVersion = appVersion, writtenBy = "", writtenAt = "")
            for (incoming in listOf(first) + copies.map { it.document }) {
                val next = LibrarySyncMerge.merging(incoming, merged.snapshot, device)
                merged = next.copy(
                    conflicts = merged.conflicts + next.conflicts,
                    certificatePinsAdded = merged.certificatePinsAdded + next.certificatePinsAdded,
                )
            }

            val written = LibraryExport.syncDocument(merged.snapshot, appVersion, atEpochMillis, device, document)
            if (!place.write(fileName, LibraryDocumentCoder.encode(written), file?.version)) return@repeat

            val undeleted = copies.filterNot { place.delete(it.name) }.map { it.key }
            return LibrarySyncOutcome.Synced(merged, skipped, mergedCopies + undeleted, copies.map { it.name })
        }
        return LibrarySyncOutcome.Busy
    }

    /** Every conflicted copy not merged before, read; one that cannot be read is named. */
    private suspend fun copies(mergedCopies: Set<String>, skipped: MutableList<String>): List<Copy> =
        place.names().filter { isConflictedCopy(it, fileName) }.sorted().mapNotNull { name ->
            val file = place.read(name) ?: return@mapNotNull null
            val key = "$name@${file.version}"
            if (key in mergedCopies) return@mapNotNull null
            val document = LibraryDocumentCoder.decode(file.text).getOrNull()
            if (document == null) skipped += name
            document?.let { Copy(name, key, it) }
        }

    private fun refusal(failure: Throwable): LibraryDocumentFailure =
        (failure as? LibraryDocumentRefusal)?.reason ?: LibraryDocumentFailure.NotALibraryDocument
}
