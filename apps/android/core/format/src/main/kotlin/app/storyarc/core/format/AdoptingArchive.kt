package app.storyarc.core.format

/**
 * An archive that can change where its bytes come from without the reader noticing.
 *
 * `offline-downloads`' *Reading while downloading* asks a publication opened by streaming to
 * "switch to the local copy when the download completes, without interrupting reading". This
 * is the switch. Every page the reader has already decoded stays decoded, the page list is
 * never rewritten, and no position is read or written here -- so a reader on page 14 is on
 * page 14 before and after, and nothing reopens under them.
 *
 * The reader wraps whatever it opened, local or streamed, so there is one shape above this
 * line rather than two. iOS's `AdoptingArchive` is the same object.
 */
class AdoptingArchive(private var reading: ComicArchiveReading) : ComicArchiveReading {

    /**
     * What [reading] took over from, held until this archive closes.
     *
     * Not closed at the moment of the swap: a page decode may be reading from it on another
     * thread, and closing a source under a read turns an invisible switch into a broken page.
     * Both are released together by [close], which the reader calls when it is done.
     */
    private var replaced: ComicArchiveReading? = null

    override val pages: List<PageEntry> get() = reading.pages

    override val skippedPageCount: Int get() = reading.skippedPageCount

    override val coverPage: PageEntry? get() = reading.coverPage

    override val doublePageIndices: List<Int> get() = reading.doublePageIndices

    override suspend fun data(page: PageEntry): ByteArray = reading.data(page)

    /**
     * Reads from [local] from now on, when it holds the same pages.
     *
     * Refused when it does not, and that is the whole of the safety here: the reader indexes
     * its pages by position, so an archive listing different entries would move every page
     * the reader has not decoded yet. A refusal leaves this archive exactly as it was and
     * closes [local], which the caller never held.
     *
     * @return whether the switch happened.
     */
    fun adopt(local: ComicArchiveReading): Boolean {
        if (local.pages != reading.pages) {
            local.close()
            return false
        }
        replaced = reading
        reading = local
        return true
    }

    override fun close() {
        reading.close()
        replaced?.close()
        replaced = null
    }
}
