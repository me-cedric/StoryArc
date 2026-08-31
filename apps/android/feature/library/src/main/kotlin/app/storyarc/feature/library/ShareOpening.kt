package app.storyarc.feature.library

import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.StreamingOffer

/**
 * What the share browser does about one publication, decided outside the composable.
 *
 * `SmbBrowserScreen` used to hold both decisions inline, and a text-reading tripwire is all a
 * JVM gate can say about a composable: `SmbTransferWiringTest` could assert that
 * `StreamingOffer.of(` appears before `onOpen(` inside `transfer`, never that the answer was
 * acted on. Deleting the judgement and calling `onOpen` unconditionally kept that order and
 * every test green -- which is the defect this change exists to fix, back with a passing
 * suite. These two functions are the same decisions with the callbacks passed in, so
 * `ShareOpeningTest` can drive them with a publication of its choosing and watch which one
 * fires. iOS keeps the same pair in `ShareOpening.swift`.
 *
 * The composable keeps what only it can do: which state a callback writes to, and which
 * dialog that state raises.
 */

/**
 * Whether a format's decoder insists on a real file.
 *
 * `PdfRenderer` needs a descriptor and libarchive needs a path, so those two are offered as a
 * download. Everything else is read where it lies.
 *
 * The platform half of [StreamingOffer]'s `readsWhereItLies`: what a container reported about
 * itself is the same question on both apps, and which decoders can work from a source is not.
 * iOS's list is longer -- its EPUB reader wants a file of its own as well.
 */
internal fun needsLocalFile(format: PublicationFormat): Boolean =
    format == PublicationFormat.PDF || format == PublicationFormat.CBR

/**
 * What the share said the file weighs, or null when it said nothing worth repeating.
 *
 * A directory entry's length is a `Long` and a share always fills one in, so the honest
 * absence [StreamingOffer.Download] carries would otherwise be unreachable from here -- and
 * the value that does arrive for an entry the server declined to size is zero. `0 B` in a
 * download offer reads as a free download, which is exactly what `offline-downloads` means by
 * requiring an absence "rather than as a zero".
 */
internal fun statedLength(length: Long): Long? = length.takeIf { it > 0L }

/**
 * Indexes a publication on the share and does what [StreamingOffer] says about it.
 *
 * Nothing is transferred here: [index] reads headers over the share, which is what lets the
 * caller state a size while it asks whether the transfer may happen at all.
 *
 * [onRefuse] is unreachable while the bytes are remote and is wired anyway -- see
 * [StreamingOffer.of], which only believes `REFUSED` once a file exists to judge. A solid RAR4
 * on a share therefore costs a whole transfer before the app can say it cannot be opened,
 * because libarchive reads `FHD_SOLID` through a path and nothing over the share can.
 */
internal suspend fun offerOrOpen(
    index: suspend () -> Pair<Publication, String>,
    length: Long,
    onOpen: (Publication, String) -> Unit,
    onOffer: (Long?) -> Unit,
    onRefuse: () -> Unit,
    onFailure: (Int) -> Unit,
) {
    runCatching { index() }
        .onSuccess { (publication, remotePath) ->
            val offer = StreamingOffer.of(
                streaming = publication.streaming,
                isLocal = false,
                readsWhereItLies = !needsLocalFile(publication.format),
                bytes = statedLength(length),
            )
            when (offer) {
                is StreamingOffer.Open -> onOpen(publication, remotePath)
                is StreamingOffer.Download -> onOffer(offer.bytes)
                is StreamingOffer.Refuse -> onRefuse()
            }
        }
        // Said out loud rather than swallowed. A tap that does nothing is the worst answer a
        // screen can give.
        .onFailure { onFailure(R.string.smb_error_unexpected) }
}

/**
 * Judges what came back from a completed transfer, then opens it or refuses it.
 *
 * The first moment the container can say what it really is: a solid RAR5 becomes
 * `DOWNLOAD_ONLY` and opens, a solid RAR4 becomes `REFUSED` and does not. The browser used to
 * open whatever came back, so a reader who had just waited for the whole file was taken to a
 * reader that cannot render page one.
 *
 * `bytes` is null rather than the entry's length: the bytes are local, so the answer is
 * [StreamingOffer.Open] or [StreamingOffer.Refuse] and neither states a size.
 */
internal suspend fun openWhatArrived(
    fetch: suspend () -> Pair<Publication, String>,
    onOpen: (Publication, String) -> Unit,
    onRefuse: () -> Unit,
    onFailure: (Int) -> Unit,
) {
    runCatching { fetch() }
        .onSuccess { (publication, local) ->
            val offer = StreamingOffer.of(
                streaming = publication.streaming,
                isLocal = true,
                readsWhereItLies = true,
                bytes = null,
            )
            if (offer is StreamingOffer.Refuse) onRefuse() else onOpen(publication, local)
        }
        .onFailure { onFailure(R.string.smb_error_unexpected) }
}
