package app.storyarc.feature.settings

import androidx.annotation.StringRes
import app.storyarc.core.model.SourceKind

/**
 * Which sentence the source detail screen states about how a source is reached.
 *
 * `network-share`'s *Encrypted transport*: "the source detail screen states whether the
 * connection is encrypted". A share is the only kind with a transport to state. A folder is
 * a disk, and the two servers are reached over HTTP.
 *
 * **Outside the screen, because the screen used to answer this with a fixed string.** The
 * sentence said the connection is not encrypted whatever the code had measured, so a test
 * that drew the screen and read the sentence back agreed with itself and proved nothing.
 * The rule is a function now, the screen calls it with the measured value, and a test can
 * pass both answers in and watch the drawn sentence follow.
 *
 * **It names encryption and never signing, and that is a decision rather than an omission.**
 * ADR-0016 refuses a signing line on iOS, because that client verifies no response and
 * cannot answer the question. jcifs-ng can answer it, and the add-share sheet says so. This
 * screen is drawn the same way on both platforms, so a signed session reads like an
 * unsigned one here.
 *
 * @param isEncrypted what the app measured, which is `ShareTransport.IS_ENCRYPTED` today.
 * @return the string to draw, or `null` when this kind of source has no transport to state.
 */
@StringRes
internal fun transportNote(kind: SourceKind, isEncrypted: Boolean): Int? = when {
    kind != SourceKind.NETWORK_SHARE -> null
    isEncrypted -> R.string.sources_detail_transport_encrypted
    else -> R.string.sources_detail_transport_plain
}
