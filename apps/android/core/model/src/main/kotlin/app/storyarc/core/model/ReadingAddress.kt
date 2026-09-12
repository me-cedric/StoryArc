package app.storyarc.core.model

/**
 * Where the reader opens a publication that may still be arriving.
 *
 * `offline-downloads`' *Reading while downloading*: a publication that is still downloading
 * "opens immediately by streaming, and switches to the local copy when the download
 * completes". Both halves are decisions about an *address*, so both live here: [of] picks the
 * address a screen opens, and [arrived] reports the local copy that may take over from a
 * streamed one.
 *
 * Held outside every screen because two screens ask it -- the publication's own page and the
 * reader -- and because a rule inside a view can only be checked by reading its text. iOS's
 * `ReadingAddress` is the same rules in the same order.
 */
object ReadingAddress {

    /**
     * The schemes a publication can be read a range at a time over.
     *
     * `HttpSource.register` teaches `PublicationAccess` these two and no others, so an
     * address outside this list is a local path to every caller above. That is why the check
     * is made rather than assumed: a download record is read back from a store on disk, and
     * an address this rule waved through would be opened as a file that does not exist.
     */
    private val STREAMED = listOf("http://", "https://")

    /** Whether this address is read over the network rather than off the disk. */
    fun isStreamed(address: String): Boolean = STREAMED.any { address.startsWith(it) }

    /**
     * The address to open, or null when there is nothing to open yet.
     *
     * @param local a copy on this device, when there is one. It always wins: a publication
     *   already here reads with no network at all, which is `offline-downloads`' whole point.
     * @param transfer the queue's record for this publication, when there is one.
     * @param readsWhereItLies whether this publication's decoder can read from a source
     *   rather than from a file. The platform half of [StreamingOffer]'s question of the same
     *   name, answered by the caller because the list of such decoders is the caller's.
     */
    fun of(local: String?, transfer: Download?, readsWhereItLies: Boolean): String? {
        if (local != null) return local
        if (!readsWhereItLies) return null
        val state = transfer?.state ?: return null
        // Queued, running and paused are all "still downloading" -- a held transfer resumes,
        // and the bytes already on the server can be read meanwhile. Finished without a local
        // copy means the file went away, and failed is a state `offline-downloads` requires
        // to be stated with a retry action rather than read past.
        if (state.isFinished || state is Download.State.Failed) return null
        return transfer.remote.takeIf(::isStreamed)
    }

    /**
     * The copy that has arrived for a publication being read at [address], or null.
     *
     * Matched on the address itself rather than on a publication identity, because the
     * address is what the reader actually opened: the transfer fetching those exact bytes is
     * the one whose file is a copy of what is on screen. A reader already on a local file has
     * nothing to switch to, so a local address matches nothing.
     */
    fun arrived(address: String, downloads: DownloadLibrary): Download? {
        if (!isStreamed(address)) return null
        return downloads.finished.firstOrNull { it.remote == address }
    }
}
