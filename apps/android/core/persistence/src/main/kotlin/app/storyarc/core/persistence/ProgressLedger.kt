package app.storyarc.core.persistence

import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingProgress

/**
 * The part of the progress store an import writes through and, on a failure, undoes through.
 *
 * A seam so a test can hand [LibraryArchive] a ledger that fails on the Nth write. [ProgressStore]
 * is the only production implementation.
 */
interface ProgressLedger {
    suspend fun recent(limit: Int = 50): List<ReadingProgress>

    suspend fun save(progress: ReadingProgress)

    suspend fun mark(
        identity: PublicationIdentity,
        isFinished: Boolean,
        at: Long = System.currentTimeMillis(),
    )

    suspend fun forget(identity: PublicationIdentity)
}
