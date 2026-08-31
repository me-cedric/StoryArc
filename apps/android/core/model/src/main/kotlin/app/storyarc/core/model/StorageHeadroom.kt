package app.storyarc.core.model

/**
 * Whether the device has room for what the download queue is about to write.
 *
 * `offline-downloads`' *Device storage is low*: "the app pauses downloads, evicts the cover
 * cache before any downloaded publication, and never deletes a download without asking".
 * Every clause of that depends on one question -- how much room is left -- and until now
 * nothing in either app asked it. [Download.Pause.OUT_OF_SPACE] and its translated sentence
 * have existed since the queue was written, in all four locales, and no code path could
 * reach them: the queue would fill the disk and say nothing.
 *
 * The rule is pure and lives here so both platforms answer it identically. Everything
 * platform-shaped -- how a volume reports free space -- stays in each app's download store,
 * which is the only part that genuinely differs. iOS keeps the same rule in
 * `StorageHeadroom.swift`, case for case.
 */
object StorageHeadroom {
    /**
     * The room the app refuses to consume, whatever it has been asked to fetch.
     *
     * A quarter of a gigabyte. Not a guess at what the *device* needs -- that is the
     * system's business -- but at what a reader needs the app to leave them: enough for a
     * photo, an update, a message thread, so that a comic the app was told to keep never
     * becomes the reason the phone stops working. `offline-downloads` allows the app to
     * pause and wait; it never allows it to take the last of the disk.
     *
     * One number rather than a fraction of the volume, because the promise is about what is
     * left rather than about proportion: a reader with 200 MB free is in the same trouble on
     * a 64 GB phone as on a 1 TB one.
     */
    const val RESERVE_BYTES: Long = 256L * 1024 * 1024

    /**
     * Whether writing [incoming] bytes now would leave the device short.
     *
     * @param free what the volume reports, or null when it would not say.
     * @param incoming what is about to be written, or null when the size is not known --
     *   which is the usual case for an OPDS acquisition, because the feed states no length.
     *   An unknown size still has to clear the floor on its own.
     *
     * **An unanswerable question is not a failure.** When the volume reports nothing this
     * returns false and the queue runs. AGENTS.md §2: a normal condition may not be turned
     * into something the reader has to dismiss, and a device that declines to state its free
     * space is not a device that is full -- pausing every download for ever on the strength
     * of a missing number would be exactly the invented failure that rule forbids.
     */
    fun isLow(free: Long?, incoming: Long? = null): Boolean {
        if (free == null) return false
        // Clamped rather than trusted: a negative free space is not a thing a volume can
        // truthfully report, and a negative incoming size would make room appear.
        val remaining = maxOf(0L, free) - maxOf(0L, incoming ?: 0L)
        return remaining < RESERVE_BYTES
    }

    /** Whether there is room, said the way a caller about to start a transfer wants it. */
    fun hasRoom(free: Long?, incoming: Long? = null): Boolean = !isLow(free, incoming)
}
