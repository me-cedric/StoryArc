package app.storyarc.feature.library

import app.storyarc.core.format.IndexException
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
 * Whether a catalogue acquisition of this format can be read from its address before the
 * download finishes.
 *
 * [readsFromAnAddress] answers the same question for a publication already indexed, and
 * knows whether an EPUB is fixed-layout. A catalogue entry has neither yet -- only a media
 * type -- so an EPUB is excluded here too: the common case is reflowable, and [needsLocalFile]
 * alone would stream a format this screen cannot yet tell apart from one it can.
 */
internal fun catalogueReadsWhereItLies(format: PublicationFormat?): Boolean =
    format != null && format != PublicationFormat.EPUB && !format.isAudio && !needsLocalFile(format)

/**
 * Whether the reader this publication opens in can read from an address rather than a file.
 *
 * The same three-way choice `AppShell` makes when a publication is opened, asked before the
 * reader is reached: the player wants a file, Readium is handed a `File` for a reflowable
 * book, and everything else goes to the comic reader, which reads through a source and
 * therefore reads over a range request.
 *
 * `offline-downloads`' *Reading while downloading* needs this answered here, because a
 * publication still arriving has an address and no file: offering *Read* for one the reader
 * cannot open from an address is worse than offering the download it already had.
 *
 * A fixed-layout EPUB is a comic to this app and is on the readable side, which is the one
 * case [needsLocalFile] alone would get wrong in either direction.
 */
internal fun readsFromAnAddress(publication: Publication): Boolean = when {
    publication.format.isAudio -> false
    publication.format == PublicationFormat.EPUB && !publication.isFixedLayout -> false
    else -> !needsLocalFile(publication.format)
}

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
 * `readsWhereItLies` comes from [readsFromAnAddress], not from [needsLocalFile] alone: a
 * reflowable EPUB cannot be read from an address either, and [needsLocalFile] does not know
 * that -- it answers "does this *format*'s decoder want a file", and a fixed-layout EPUB is
 * read through the comic path regardless of format.
 *
 * The [CANNOT_OPEN] branch is reachable here now: `RarComicArchive` detects a solid RAR4 from
 * its headers alone, so [StreamingOffer.of] believes `REFUSED` whether or not the bytes are
 * local, and a solid RAR4 on a share is refused before the whole file is transferred.
 */
internal suspend fun offerOrOpen(
    index: suspend () -> Pair<Publication, String>,
    length: Long,
    onOpen: (Publication, String) -> Unit,
    onOffer: (Long?) -> Unit,
    onSay: (Int) -> Unit,
) {
    runCatching { index() }
        .onSuccess { (publication, remotePath) ->
            val offer = StreamingOffer.of(
                streaming = publication.streaming,
                isLocal = false,
                readsWhereItLies = readsFromAnAddress(publication),
                bytes = statedLength(length),
            )
            when (offer) {
                is StreamingOffer.Open -> onOpen(publication, remotePath)
                is StreamingOffer.Download -> onOffer(offer.bytes)
                is StreamingOffer.Refuse -> onSay(CANNOT_OPEN)
            }
        }
        .onFailure { error -> onSay(sentenceForIndexFailure(error)) }
}

/**
 * Which sentence an index failure over a share earns.
 *
 * The indexer already throws a typed [IndexException] for a `.cb7`, a protected archive or a
 * damaged one -- headers it read over the share, not a network failure -- and
 * `offerOrOpen` used to send every one of those to [UNEXPECTED] regardless, which reads as
 * "the share could not be reached" for a file the share reached just fine. [UNEXPECTED]
 * stays for an actual network failure (`SmbError` and anything else this did not expect).
 */
private fun sentenceForIndexFailure(error: Throwable): Int = when (error) {
    is IndexException.Unsupported -> UNSUPPORTED
    is IndexException.ArchivePasswordProtected -> PASSWORD_PROTECTED
    is IndexException.ArchiveUnreadable -> DAMAGED
    else -> UNEXPECTED
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
    onSay: (Int) -> Unit,
) {
    runCatching { fetch() }
        .onSuccess { (publication, local) ->
            val offer = StreamingOffer.of(
                streaming = publication.streaming,
                isLocal = true,
                readsWhereItLies = true,
                bytes = null,
            )
            if (offer is StreamingOffer.Refuse) onSay(CANNOT_OPEN) else onOpen(publication, local)
        }
        .onFailure { onSay(UNEXPECTED) }
}

/**
 * The refusal `publication-formats` requires to be named rather than retried.
 *
 * Named here rather than in the composable, so that the decision owns the sentence it leads to
 * and [ShareOpeningTest] can assert *which* sentence a publication earns. iOS keeps the pair as
 * `ShareOpening.cannotOpen` and `ShareOpening.unexpected` for the same reason.
 */
internal val CANNOT_OPEN: Int = R.string.detail_refused_body

/**
 * Said out loud rather than swallowed. A tap that does nothing is the worst answer a screen can
 * give.
 */
internal val UNEXPECTED: Int = R.string.smb_error_unexpected

/** Named, the same claim Open-in's refusal makes: the container is recognised and refused. */
internal val UNSUPPORTED: Int = R.string.smb_error_unsupported

/** No password field here either -- StoryArc does not manage archive passwords. */
internal val PASSWORD_PROTECTED: Int = R.string.smb_error_password_protected

/** Damaged, not unsupported: the format is one StoryArc reads. */
internal val DAMAGED: Int = R.string.smb_error_damaged
