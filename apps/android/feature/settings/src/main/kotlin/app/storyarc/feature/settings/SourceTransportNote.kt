package app.storyarc.feature.settings

import androidx.annotation.StringRes
import app.storyarc.core.model.ShareTransport
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
 * ADR-0016 refuses a signing line on iOS. This screen is drawn the same way on both
 * platforms, so a signed session reads like an unsigned one here.
 *
 * Three whole sentences, one per state, never a clause added to another: French, German and
 * Spanish order the words differently.
 *
 * @param transport what the last session with this share negotiated, or `null` when the app
 *   has not reached it since it started.
 * @return the sentence to draw, or `null` when this kind of source has no transport to state.
 */
internal fun transportNote(kind: SourceKind, transport: ShareTransport?): TransportNote? = when {
    kind != SourceKind.NETWORK_SHARE -> null
    transport == null -> TransportNote(R.string.sources_detail_transport_unknown)
    transport.isEncrypted -> TransportNote(R.string.sources_detail_transport_encrypted, transport.dialect)
    else -> TransportNote(R.string.sources_detail_transport_plain, transport.dialect)
}

/** One sentence, and the dialect it names when it names one. */
internal data class TransportNote(@StringRes val text: Int, val dialect: String? = null)
