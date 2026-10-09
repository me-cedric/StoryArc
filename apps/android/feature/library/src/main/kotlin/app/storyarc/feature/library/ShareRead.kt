package app.storyarc.feature.library

import android.text.format.Formatter
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import app.storyarc.core.designsystem.control.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import app.storyarc.core.model.Publication
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * How the library's own page opens a row whose bytes are on a network share.
 *
 * `SmbContributor` files a share row under the share's own `smb://` address, so the
 * publication page already holds an address `PublicationAccess`'s registered opener can take.
 * What the page did not hold is the two things the share browser owes the identical file:
 * `network-share`'s *Metered connection* requires "explicit confirmation before streaming or
 * downloading" on such a link, and `publication-formats` requires a format that cannot be read
 * where it lies to state its size and offer a download rather than open and fail.
 *
 * [offerOrOpen] is the browser's own rule, asked here with the shelf's row in place of a ranged
 * index read: `SmbContributor` already took the format, the streaming capability and the length
 * from the share's directory entry, so a second round trip would only ask the share what the
 * shelf already knows. iOS's `ShareRead.swift` is its twin.
 *
 * ---
 *
 * Whether this location is a share this app browses rather than a file it holds.
 *
 * A scheme test rather than `PublicationAccess.isRemote`, for the reason [isOnDevice] already
 * states: that one answers from a table the app layer fills at start-up, so it is true or false
 * depending on how far the app has booted, and a JVM test cannot assert it at all.
 */
fun isShareLocation(location: String?): Boolean = location?.startsWith("smb://") == true

/** What a tap on a share row owes the reader before anything is opened. */
internal sealed interface ShareAsk {
    /** The link is one to be careful with, so the reader confirms before bytes move. */
    data object Metered : ShareAsk

    /** This format cannot be read where it lies. The size, where the share stated one. */
    data class Download(val bytes: Long?) : ShareAsk

    /** Nothing will open this, here or anywhere, and the notice says which refusal. */
    data class Said(val notice: ShareNotice) : ShareAsk
}

/**
 * What the page does next about [publication], which lives at [address] on a share.
 *
 * Null means open it at that address now. Free of Compose so `ShareReadTest` can state every
 * answer without a composition, which is the lesson `ShareOpeningTest` records: a decision only
 * a text search can reach is a decision a green suite can lose.
 */
internal suspend fun shareReadStep(
    publication: Publication,
    address: String,
    isCareful: Boolean,
    hasConfirmedMetered: Boolean,
): ShareAsk? {
    if (isCareful && !hasConfirmedMetered) return ShareAsk.Metered
    var opened = false
    var ask: ShareAsk? = null
    offerOrOpen(
        name = publication.displayTitle,
        index = { publication to address },
        length = publication.fileSize ?: 0L,
        onOpen = { _, _ -> opened = true },
        onOffer = { bytes -> ask = ShareAsk.Download(bytes) },
        onSay = { said -> ask = ShareAsk.Said(said) },
    )
    return if (opened) null else ask
}

/**
 * The publication page's share-row tap, and the answer it is waiting on.
 *
 * Holds the pending ask and nothing else: the publication, the address and what to do with
 * them are the page's, handed in per press, so this survives a recomposition without the page
 * having to keep its lambdas stable.
 */
internal class ShareReading(
    private val ask: MutableState<ShareAsk?>,
    private val isCareful: Boolean,
    private val scope: CoroutineScope,
) {
    /** What the reader is being asked, and null when they are being asked nothing. */
    val pending: ShareAsk? get() = ask.value

    /** The primary action: a share row is judged, and every other row opens as it always did. */
    fun press(publication: Publication, address: String?, onOpen: () -> Unit) {
        if (!isShareLocation(address) || address == null) return onOpen()
        decide(publication, address, hasConfirmedMetered = false, onOpen)
    }

    /** The reader agreed to spend the metered link, so the offer is asked next. */
    fun confirmMetered(publication: Publication, address: String, onOpen: () -> Unit) {
        ask.value = null
        decide(publication, address, hasConfirmedMetered = true, onOpen)
    }

    fun dismiss() {
        ask.value = null
    }

    private fun decide(
        publication: Publication,
        address: String,
        hasConfirmedMetered: Boolean,
        onOpen: () -> Unit,
    ) {
        scope.launch {
            val next = shareReadStep(publication, address, isCareful, hasConfirmedMetered)
            if (next == null) onOpen() else ask.value = next
        }
    }
}

/** The page's own [ShareReading], with the link's cost read once per composition. */
@Composable
internal fun rememberShareReading(): ShareReading = ShareReading(
    ask = remember { mutableStateOf(null) },
    isCareful = NetworkCost.isCareful(LocalContext.current),
    scope = rememberCoroutineScope(),
)

/**
 * The three answers a share row's primary action may owe, drawn as `SmbBrowserScreen` draws
 * them: the same titles, the same bodies and the same byte formatter, because one file reached
 * two ways must not be described two ways.
 */
@Composable
internal fun ShareReadDialogs(
    reading: ShareReading,
    publication: Publication,
    address: String?,
    onDownload: (() -> Unit)?,
    onOpen: () -> Unit,
) {
    val context = LocalContext.current
    val cancel: @Composable () -> Unit = {
        TextButton(onClick = reading::dismiss) {
            Text(stringResource(R.string.shelves_cancel))
        }
    }

    when (val ask = reading.pending) {
        null -> Unit

        // `network-share`'s *Metered connection*, on the publication page rather than only in
        // the share browser.
        is ShareAsk.Metered -> AlertDialog(
            onDismissRequest = reading::dismiss,
            title = { Text(stringResource(R.string.smb_metered_title)) },
            text = { Text(stringResource(R.string.smb_metered_body, publication.displayTitle)) },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (address != null) reading.confirmMetered(publication, address, onOpen)
                    },
                ) {
                    Text(stringResource(R.string.smb_metered_continue))
                }
            },
            dismissButton = cancel,
        )

        // `publication-formats`: a publication that cannot be read where it lies is named,
        // sized and offered -- never streamed badly into a stalled page.
        is ShareAsk.Download -> AlertDialog(
            onDismissRequest = reading::dismiss,
            title = { Text(stringResource(R.string.smb_download_first_title)) },
            text = {
                Text(
                    if (ask.bytes != null) {
                        stringResource(
                            R.string.smb_download_first_body,
                            publication.displayTitle,
                            Formatter.formatShortFileSize(context, ask.bytes),
                        )
                    } else {
                        stringResource(
                            R.string.smb_download_first_body_unstated,
                            publication.displayTitle,
                        )
                    },
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        reading.dismiss()
                        onDownload?.invoke()
                    },
                    enabled = onDownload != null,
                ) {
                    Text(stringResource(R.string.catalogue_acquire_download))
                }
            },
            dismissButton = cancel,
        )

        // The refusal `offerOrOpen` named, said rather than swallowed.
        is ShareAsk.Said -> AlertDialog(
            onDismissRequest = reading::dismiss,
            text = {
                Text(stringResource(ask.notice.textRes, *ask.notice.args.toTypedArray()))
            },
            confirmButton = {
                TextButton(onClick = reading::dismiss) {
                    Text(stringResource(R.string.library_import_dismiss))
                }
            },
        )
    }
}
