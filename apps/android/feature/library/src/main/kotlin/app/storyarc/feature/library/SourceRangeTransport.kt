package app.storyarc.feature.library

import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.catalogue.OpdsOrigin
import app.storyarc.core.catalogue.OpdsTrust
import app.storyarc.core.format.HttpAnswer
import app.storyarc.core.format.RangeTransport
import app.storyarc.core.model.Source
import app.storyarc.core.persistence.CredentialStore
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import javax.net.ssl.HttpsURLConnection
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The range transport the app registers for a streamed read.
 *
 * `offline-downloads`' *Reading while downloading* streams a catalogue's own acquisition
 * address, over the same rules the download queue applies to it: only the configured
 * source's credential travels, only to that source's own origin, and only a certificate the
 * reader trusts opens the connection. `HttpSource`'s default transport
 * (`UrlConnectionRangeTransport`) is unauthenticated and unpinned, which answers 401 or fails
 * TLS the moment a catalogue behind either asks for it -- `HttpSource.kt`'s own default and
 * `AppDependencies`'s old `HttpSource.register()` registered it anyway, because nothing else
 * existed to register.
 *
 * `core:format` must not learn what a keystore is, so this lives beside the app's other
 * sources of truth -- `feature:library`, which already reads both `core:catalogue` and
 * `core:persistence` -- rather than in `core:format` itself. iOS's `SourceRangeTransport` is
 * the same fix.
 *
 * @param sources read fresh on every fetch, never captured, so a credential entered after
 *   this transport was registered is found the next time it is asked for rather than only
 *   after the app relaunches.
 */
class SourceRangeTransport(
    private val pins: CertificatePins,
    private val credentials: CredentialStore?,
    private val sources: () -> List<Source>,
) : RangeTransport {

    override suspend fun fetch(url: String, from: Long, through: Long): HttpAnswer =
        withContext(Dispatchers.IO) {
            if (!OpdsOrigin.isFetchable(url)) throw SourceRangeTransportException.Unfetchable
            val origin = OpdsOrigin.of(url)
            if (origin?.downgrades(url) == true) throw SourceRangeTransportException.Downgraded

            val connection = URI(url).toURL().openConnection() as HttpURLConnection
            try {
                connection.requestMethod = "GET"
                connection.setRequestProperty("Range", "bytes=$from-$through")
                connection.useCaches = false
                connection.connectTimeout = TIMEOUT_MILLIS
                connection.readTimeout = TIMEOUT_MILLIS
                val credential = origin?.let(::credentialFor)
                if (credential != null) {
                    connection.setRequestProperty("Authorization", credential.header)
                }
                if (connection is HttpsURLConnection) OpdsTrust.install(connection, pins)

                val status = connection.responseCode
                val stream = if (status >= 400) connection.errorStream else connection.inputStream
                HttpAnswer(
                    status = status,
                    body = stream?.use { it.readBytes() } ?: ByteArray(0),
                    contentRange = connection.getHeaderField("Content-Range"),
                    url = connection.url?.toString() ?: url,
                )
            } finally {
                connection.disconnect()
            }
        }

    /**
     * The credential of the one registered source whose own address is this origin, or null
     * when none is -- an address the reader typed, or a source with no secret.
     */
    private fun credentialFor(origin: OpdsOrigin): OpdsCredential? {
        val reference = sourceEligibleFor(origin)?.credentialReference ?: return null
        return credentials?.secret(reference)?.let(OpdsCredential::of)
    }

    /**
     * The one registered source whose own address is this origin, or null when none is.
     *
     * Split out of [credentialFor] so a test can ask it directly: the platform Keystore
     * behind [credentials] only a device or an emulator can open, and this is the half of
     * the decision that does not need one. Internal, not private, for exactly that test.
     */
    internal fun sourceEligibleFor(origin: OpdsOrigin): Source? =
        sources().firstOrNull { candidate ->
            candidate.locator?.let(OpdsOrigin::of) == origin
        }

    private companion object {
        const val TIMEOUT_MILLIS = 30_000
    }
}

/**
 * Why a range request never left the device.
 *
 * Both mean the address is not one this transport will touch at all, before any request is
 * made -- the same two refusals `OpdsClient` makes of a feed address, restated here because a
 * streamed publication's acquisition link is exactly the same kind of address.
 */
sealed class SourceRangeTransportException(message: String) : IOException(message) {
    /** Not `http` or `https`. */
    object Unfetchable : SourceRangeTransportException("not an http(s) address")

    /** `https` stepping down to cleartext. */
    object Downgraded : SourceRangeTransportException("stepped down from https to http")
}
