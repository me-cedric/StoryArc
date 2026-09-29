package app.storyarc.feature.reader

import android.graphics.Bitmap
import app.storyarc.core.format.PageCodec
import app.storyarc.core.format.PageDecoder
import app.storyarc.core.format.PageEntry
import app.storyarc.core.model.PublicationFormat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Keeping the pages around the reader decoded, and dropping the rest.
 *
 * `comic-reader` requires a turn to be immediate, which means the next page has to be
 * decoded before it is asked for. This is the window that does that, the pressure rule
 * that narrows it, and the tracking `NetworkNotice` reads for the page on screen.
 *
 * Split from `ReaderViewModel.kt` when that file passed the line cap. iOS keeps the same
 * split, into `ReaderDecoding.swift`, for the same reason.
 */

/** Decodes the page at [index] and its neighbours, and drops the rest. */
suspend fun ReaderViewModel.warm(index: Int) {
    if (index != currentIndex) {
        // The trouble belongs to the page being left. A page turned to while its prefetch
        // is still reading has been waiting since this turn; `decode` sets the wait itself
        // for a read it starts. Guarded so `noteMemoryPressure` re-warming the same index
        // does not wipe a failure that is still going on.
        currentIndex = index
        pageFailingSince = null
        pageWaitStarted = System.currentTimeMillis().takeIf { isShare && index in reading }
    }
    record(index)
    val pageList = pages.value
    val wanted = prefetch.pages(around = index, of = pageList.size)
    // Dropped before decoding, so peak memory is the window and not the window plus
    // whatever was there before.
    (decoded.keys - wanted).forEach {
        decoded.remove(it)
        attempted.remove(it)
        refusedCodecs.remove(it)
    }
    // A zoom held on a page the reader has moved away from is the same waste as a
    // decoded page outside the window, only three times the size.
    zoomed?.let { if (it.index !in wanted) zoomed = null }
    // The current page first: a turn should not wait on its neighbours.
    for (target in listOf(index) + wanted.sortedBy { kotlin.math.abs(it - index) }) {
        if (target !in pageList.indices || target in attempted) continue
        decode(target, pageList[target])
    }
}

/**
 * One decode of one page, and what it settled.
 *
 * The distinction between the last two cases is the reason this exists. Both used to be
 * "no bitmap", and treating a refusal as a missing read left the reader spinning for ever
 * on a page nothing was ever going to produce.
 */
private sealed interface PageOutcome {
    data class Decoded(val bitmap: Bitmap) : PageOutcome

    /**
     * The bytes arrived and the decoder would not have them. Permanent for this file, and
     * [codec] is what `publication-formats` wants named in the placeholder — null when the
     * bytes say nothing recognisable at all.
     */
    data class Refused(val codec: String?) : PageOutcome

    /** The bytes could not be read. Usually the source is away, so it is worth asking again. */
    data object Unread : PageOutcome
}

/**
 * Only the page on screen, and only for a share: `network-share`'s notice is about *that*
 * page's own trouble, not a prefetched neighbour's, and a plain local file offers no
 * download-for-offline and no "share" to name.
 */
private val ReaderViewModel.isShare: Boolean get() = path.startsWith("smb://")

private suspend fun ReaderViewModel.decode(index: Int, page: PageEntry) {
    attempted += index
    if (isShare && index == currentIndex) pageWaitStarted = System.currentTimeMillis()
    reading += index
    val result = try {
        outcome(index, page, maxPixelSize)
    } finally {
        reading -= index
    }
    // Asked again now that the read has ended: a prefetch the reader turned to while it was
    // reading is the page on screen, and its wait is the one the notice counts.
    val isOnScreen = isShare && index == currentIndex
    val waitedSince = pageWaitStarted.takeIf { isOnScreen }
    if (isOnScreen) pageWaitStarted = null

    when (result) {
        is PageOutcome.Decoded -> {
            val bitmap = result.bitmap
            decoded[index] = bitmap
            refusedCodecs.remove(index)
            // The first few pages that decode settle the implied scroll axis. Early
            // rather than every page: waiting for the tallest of the whole run would
            // mean waiting for the whole publication.
            if (bitmap.width > 0) {
                earlyTallness.note(bitmap.height.toDouble() / bitmap.width, index)
            }
            // Wider than tall, with no tolerance to tune: a portrait page scanned with a
            // slight skew is still portrait, and a spread is half again as wide as a page.
            if (bitmap.width > bitmap.height) wide += index
            if (isOnScreen) pageFailingSince = null
        }

        is PageOutcome.Refused -> {
            // Remembered as tried, which is what makes the placeholder appear: the bytes
            // are here and the decoder will say the same thing about them next time.
            result.codec?.let { refusedCodecs[index] = it }
            if (isOnScreen) pageFailingSince = null
        }

        PageOutcome.Unread -> {
            // Forgotten rather than remembered as tried. A page that failed because the
            // share was away must be readable once it comes back -- `network-share` asks
            // the app to "resume streaming at the current page" after reconnecting, and a
            // page marked attempted for ever never gets a second chance.
            attempted.remove(index)
            // The *first* failure only, and timed from when the page began to wait rather
            // than from when the read gave up: the notice then keeps counting through the
            // failure and through the gaps between `watchForPageRecovery`'s retries.
            if (isOnScreen && pageFailingSince == null) {
                pageFailingSince = waitedSince ?: System.currentTimeMillis()
            }
        }
    }
}

private suspend fun ReaderViewModel.outcome(index: Int, page: PageEntry, size: Int): PageOutcome {
    val reader = pdf
    if (reader != null) {
        val rendered = withContext(Dispatchers.IO) {
            pdfLock.withLock { runCatching { reader.render(index, size) }.getOrNull() }
        }
        // A PDF page is drawn rather than stored, so there are no codec bytes to sniff.
        // The format is still what was refused, and naming it is the point:
        // `publication-formats` asks for "the codec or format".
        return rendered?.let { PageOutcome.Decoded(it) }
            ?: PageOutcome.Refused(PublicationFormat.PDF.displayName)
    }
    val opened = archive ?: return PageOutcome.Unread
    return withContext(Dispatchers.IO) {
        val data = runCatching { opened.data(page) }.getOrNull()
            ?: return@withContext PageOutcome.Unread
        runCatching { PageDecoder.decode(data, size) }.getOrNull()
            ?.let { PageOutcome.Decoded(it) }
            ?: PageOutcome.Refused(PageCodec.nameOf(data, page.path))
    }
}

/** The same decode, without the bookkeeping, for a zoom that wants one page larger. */
internal suspend fun ReaderViewModel.decodeBitmap(index: Int, page: PageEntry, size: Int): Bitmap? =
    (outcome(index, page, size) as? PageOutcome.Decoded)?.bitmap

/**
 * Re-reads the page on screen at a short interval while it has not arrived, so streaming
 * resumes at the current page without the reader turning away and back.
 *
 * `network-share`'s *Connection drops while reading*: `warm`'s only other caller is
 * `noteMemoryPressure`, which does not fire on its own while the reader sits still on one
 * page waiting -- a page that failed stayed a spinner until a turn away and back asked for
 * it again.
 */
suspend fun ReaderViewModel.watchForPageRecovery() {
    while (true) {
        delay(RECOVERY_INTERVAL_MILLIS)
        recoverCurrentPage()
    }
}

/** One round of [watchForPageRecovery]: reads the page on screen again when it still needs a read. */
internal suspend fun ReaderViewModel.recoverCurrentPage() {
    val index = currentIndex
    val needed = needsRecovery(
        currentIndex = index,
        pageCount = pages.value.size,
        decoded = decoded.keys,
        attempted = attempted,
        refused = refusedCodecs.keys,
    )
    if (!needed) return
    val page = pages.value.getOrNull(index) ?: return
    decode(index, page)
}

private const val RECOVERY_INTERVAL_MILLIS = 3_000L

/**
 * Whether the page on screen still needs a read, lifted beside [watchForPageRecovery] so a
 * test can hold the rule without owning a publication to wait on.
 *
 * Not already in flight: `decode` inserts into `attempted` before it awaits, and only a
 * failure removes the entry again -- so a page mid-read reads as attempted here, and this
 * declines to ask again under it.
 */
fun needsRecovery(
    currentIndex: Int,
    pageCount: Int,
    decoded: Set<Int>,
    attempted: Set<Int>,
    refused: Set<Int>,
): Boolean =
    currentIndex in 0 until pageCount &&
        currentIndex !in decoded &&
        currentIndex !in refused &&
        currentIndex !in attempted
