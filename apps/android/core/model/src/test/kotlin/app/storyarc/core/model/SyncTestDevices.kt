package app.storyarc.core.model

/**
 * A sync place in memory: files by name, each with a version that moves on every write.
 *
 * [beforeWrite] runs once before the next write, so a test can let another device write in
 * between a read and a write. [undeletable] names files whose delete fails.
 */
class MemoryPlace : SyncPlace {
    val files = linkedMapOf<String, SyncFile>()
    var beforeWrite: (suspend () -> Unit)? = null
    val undeletable = mutableSetOf<String>()
    var writes = 0
    private var version = 0

    fun put(name: String, text: String) {
        files[name] = SyncFile(text, "v${++version}")
    }

    fun document(): LibraryDocument =
        LibraryDocumentCoder.decode(files.getValue(LibrarySync.FILE_NAME).text).getOrThrow()

    override suspend fun names(): List<String> = files.keys.toList()

    override suspend fun read(name: String): SyncFile? = files[name]

    override suspend fun write(name: String, text: String, replacing: String?): Boolean {
        beforeWrite?.let { hook ->
            beforeWrite = null
            hook()
        }
        if (files[name]?.version != replacing) return false
        writes++
        put(name, text)
        return true
    }

    override suspend fun delete(name: String): Boolean {
        if (name in undeletable) return false
        return files.remove(name) != null
    }
}

/**
 * One device: its library in memory, as its stores would hold it after each sync.
 *
 * [sync] writes the merged snapshot back as the stores would, and keeps the conflicted copies
 * it could not delete, as `LibrarySyncState` does.
 */
class SyncDevice(val id: String, var library: LibrarySnapshot = LibrarySnapshot()) {
    var mergedCopies: Set<String> = emptySet()
    val conflicts = mutableListOf<ProgressPull.Conflict>()

    suspend fun sync(place: SyncPlace, at: Long): LibrarySyncOutcome {
        val outcome = LibrarySync(place, id, "1.0").sync(library, at, mergedCopies)
        if (outcome is LibrarySyncOutcome.Synced) {
            library = outcome.merged.snapshot
            mergedCopies = outcome.mergedCopies
            conflicts += outcome.merged.conflicts
        }
        return outcome
    }

    fun position(identity: PublicationIdentity): ReadingProgress? =
        library.progress.firstOrNull { it.identity.matches(identity) }

    /** Reads to [page] of [total] at [at], the way the reader's save writes a position. */
    fun read(identity: PublicationIdentity, page: Int, total: Int = 100, at: Long) {
        val held = position(identity)
        val record = held?.copy(position = ReadingPosition.Page(page, total), updatedAtEpochMillis = at)
            ?: ReadingProgress(identity, ReadingPosition.Page(page, total), updatedAtEpochMillis = at)
        library = library.copy(progress = library.progress.filterNot { it.identity.matches(identity) } + record)
    }
}

/** Moments a test reads easily: [second] seconds after a fixed day. */
fun moment(second: Long): Long = 1_767_225_600_000L + second * 1_000L
