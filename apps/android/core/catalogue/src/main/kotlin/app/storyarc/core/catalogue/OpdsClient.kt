package app.storyarc.core.catalogue

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLHandshakeException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * How a catalogue is asked who is calling.
 *
 * `opds-catalog` requires "HTTP Basic and Bearer tokens". Both are secrets, so this type
 * deliberately has no `toString` worth logging -- see [header].
 */
sealed class OpdsCredential {
    data class Basic(val user: String, val password: String) : OpdsCredential()
    data class Bearer(val token: String) : OpdsCredential()

    /**
     * The credential written as one string, for the secure store.
     *
     * Newline-separated and scheme-first. A colon would be ambiguous -- a password may
     * contain one -- and something has to say whether the stored secret is a token or a
     * pair, or a reader signed in with Bearer is sent back as Basic on the next launch.
     */
    val stored: String
        get() = when (this) {
            is Basic -> "basic\n$user\n$password"
            is Bearer -> "bearer\n$token"
        }

    companion object {
        /**
         * Reads back what [stored] wrote.
         *
         * Split once for the scheme, then once more for the pair. Splitting on every
         * newline would truncate a password that contains one, and a password pasted from a
         * manager can. A user name with a newline in it is not a case anyone has.
         */
        fun of(stored: String): OpdsCredential? {
            val head = stored.split("\n", limit = 2)
            if (head.size != 2 || head[1].isEmpty()) return null
            return when (head[0]) {
                "basic" -> {
                    val pair = head[1].split("\n", limit = 2)
                    if (pair.size != 2) null else Basic(pair[0], pair[1])
                }
                "bearer" -> Bearer(head[1])
                else -> null
            }
        }
    }

    /**
     * The `Authorization` header value.
     *
     * Built at the moment of use and not retained, which is the same rule the credential
     * store follows: `sources` forbids a secret in "preferences, logs, crash reports,
     * backups, or exported diagnostics", and a value held longer than the request is a
     * value something else can read.
     */
    internal val header: String
        get() = when (this) {
            // `java.util.Base64`, not `android.util.Base64`: the same output, and it runs
            // in a JVM unit test. minSdk is 31, so it is available everywhere this ships.
            is Basic -> "Basic " + java.util.Base64.getEncoder()
                .encodeToString("$user:$password".toByteArray())
            is Bearer -> "Bearer $token"
        }
}

/**
 * Fetches OPDS feeds and the files they point at.
 *
 * `HttpURLConnection` rather than a new dependency. The app makes one kind of request --
 * a GET with two optional headers -- and the platform has done that since API 1. iOS uses
 * `URLSession` for the same reason.
 */
class OpdsClient(
    private val pins: CertificatePins = CertificatePins(),
    /**
     * The origin of the source this client was made for, or null when the caller is asking
     * about an address the reader typed and there is nothing else to compare it against.
     */
    private val origin: OpdsOrigin? = null,
) {

    /**
     * Both dialects, and Atom last.
     *
     * A server that speaks both should hand over the JSON one -- it is the version with a
     * future -- but every server speaks Atom, so it stays in the list rather than being
     * assumed.
     */
    private val accept = listOf(
        "application/opds+json",
        "application/atom+xml;profile=opds-catalog",
        "application/atom+xml",
        "*/*;q=0.1",
    ).joinToString(", ")

    /** One page of a catalogue. */
    suspend fun feed(url: String, credential: OpdsCredential? = null): OpdsFeed {
        val fetched = fetch(url, credential)
        return OpdsDocument.parse(
            fetched.body,
            contentType = fetched.contentType,
            // Where the response came from, not where the request went. A redirect moves
            // what a relative href is relative to, and resolving against the request would
            // point every link on the page at the wrong host.
            baseUrl = fetched.url,
        )
    }

    /** A file the catalogue pointed at -- a cover, or a publication being downloaded. */
    suspend fun bytes(url: String, credential: OpdsCredential? = null): ByteArray =
        fetch(url, credential).body

    /**
     * The certificate refused since this client was last asked.
     *
     * Read after a failure, so the UI can show the fingerprint and offer to pin it. Null
     * when the failure was something else, which is what stops a network timeout from
     * being presented as a certificate question.
     */
    fun lastRefusedCertificate(): UntrustedCertificate? = refused.getAndSet(null)

    private val refused = java.util.concurrent.atomic.AtomicReference<UntrustedCertificate?>(null)

    private class Fetched(val body: ByteArray, val contentType: String?, val url: String)

    /** One hop: either the answer, or where the server says to look instead. */
    private sealed interface Hop {
        class Done(val fetched: Fetched) : Hop
        class Moved(val location: String) : Hop
    }

    /**
     * Follows the address, and every redirect it is sent on, by hand.
     *
     * `instanceFollowRedirects` is turned off because the platform's own following makes
     * the origin decision invisible: it re-issues the request itself, and whether the
     * `Authorization` header survives is left to a rule this app cannot see or test. Doing
     * it here means every hop is checked against the same origin -- the *first* one's, not
     * the previous hop's, or a chain of two redirects arrives anywhere with the header
     * intact.
     */
    private suspend fun fetch(url: String, credential: OpdsCredential?): Fetched =
        withContext(Dispatchers.IO) {
            // The configured source's origin, or -- for an address the reader typed, which
            // has nothing to be compared against -- its own.
            val home = origin ?: OpdsOrigin.of(url)
            var target = url
            var hops = 0
            while (true) {
                when (val hop = one(target, credential, home)) {
                    is Hop.Done -> return@withContext hop.fetched
                    is Hop.Moved -> {
                        if (++hops > MAX_REDIRECTS) throw OpdsError.RefusedAddress
                        target = URI(target).resolve(hop.location).toString()
                    }
                }
            }
            @Suppress("UNREACHABLE_CODE")
            throw OpdsError.Empty
        }

    private fun one(url: String, credential: OpdsCredential?, home: OpdsOrigin?): Hop {
        // The origin decides, and it is the configured source's -- not the address in hand.
        // A feed that names `http://collect.attacker.example/x` names it in the same field a
        // legitimate cover comes in, and the cover field is fetched with no tap at all.
        if (!OpdsOrigin.isFetchable(url)) throw OpdsError.RefusedAddress
        if (home?.downgrades(url) == true) throw OpdsError.RefusedAddress

        // `as?`, not `as`: `openConnection()` on a scheme this app does not fetch returns a
        // connection that is not an `HttpURLConnection`, and the unchecked cast threw a
        // `ClassCastException` no catch clause in the app matched.
        val connection = URL(url).openConnection() as? HttpURLConnection
            ?: throw OpdsError.RefusedAddress
        connection.requestMethod = "GET"
        connection.instanceFollowRedirects = false
        connection.connectTimeout = TIMEOUT_MILLIS
        connection.readTimeout = TIMEOUT_MILLIS
        connection.setRequestProperty("Accept", accept)
        if (credential != null && home?.admits(url) == true) {
            connection.setRequestProperty("Authorization", credential.header)
        }
        // Nothing is cached to disk. A catalogue response can name a reader's whole
        // library, and `settings-and-about` promises no data leaves the device that the
        // reader did not send -- a cache on disk is a copy nobody asked for.
        connection.useCaches = false

        val untrusted = if (connection is HttpsURLConnection) {
            OpdsTrust.install(connection, pins)
        } else {
            null
        }

        try {
            val status = try {
                connection.responseCode
            } catch (error: SSLHandshakeException) {
                // The certificate is the story, and the handshake exception is not.
                val certificate = untrusted?.get()
                if (certificate != null) {
                    refused.set(certificate)
                    throw OpdsRefusal.Untrusted(certificate)
                }
                throw error
            }

            when {
                status in 200..299 -> Unit
                status in 300..399 -> {
                    val location = connection.getHeaderField("Location")
                        ?: throw OpdsError.Http(status)
                    return Hop.Moved(location)
                }
                // Which scheme, so the prompt can ask for the right thing. A server
                // that wants a token and is handed a username fails in a way that looks
                // like a wrong password.
                status == 401 -> throw OpdsError.Unauthorized(
                    connection.getHeaderField("WWW-Authenticate")
                        ?.let(OpdsError.AuthenticationScheme::of),
                )
                else -> throw OpdsError.Http(status)
            }

            val body = connection.inputStream.use { it.readBytes() }
            if (body.isEmpty()) throw OpdsError.Empty
            return Hop.Done(Fetched(body, connection.contentType, url))
        } finally {
            connection.disconnect()
        }
    }

    private companion object {
        const val TIMEOUT_MILLIS = 20_000

        /** What a browser allows too. A server that needs more is looping. */
        const val MAX_REDIRECTS = 5
    }
}

/**
 * A refusal that carries what was refused.
 *
 * Separate from [OpdsError] because it is not a parsing outcome and not an HTTP status: it
 * is a decision this app made, and the reader can reverse it.
 */
sealed class OpdsRefusal(message: String) : IOException(message) {
    data class Untrusted(val certificate: UntrustedCertificate) :
        OpdsRefusal("untrusted certificate for ${certificate.host}")
}

/** A certificate the system would not vouch for, described so a reader can decide. */
data class UntrustedCertificate(
    val host: String,
    /**
     * SHA-256 of the DER, in the colon-separated hex every other tool prints. Shown to the
     * reader, because "do you trust this server" is not a question anyone can answer and
     * "does this fingerprint match the one your server printed" is.
     */
    val fingerprint: String,
    val subject: String,
    val notValidAfter: java.util.Date?,
)

/**
 * Which server certificates the reader has explicitly accepted.
 *
 * `opds-catalog`: a catalogue presenting a certificate the system does not trust is refused
 * "by default", and the app "offers to pin that specific certificate after showing its
 * fingerprint and an explicit warning". So there are two states, not one -- untrusted and
 * refused, or untrusted and named by the reader -- and this holds the second.
 *
 * One certificate, one host. A pin is not "trust this server for anything"; it is "this
 * exact certificate, on this exact host". A pin that widened to a whole CA would let a
 * self-hosted server vouch for the rest of the internet.
 */
class CertificatePins(initial: Map<String, Set<String>> = emptyMap()) {
    private val pinned = java.util.concurrent.ConcurrentHashMap<String, MutableSet<String>>()

    init {
        initial.forEach { (host, fingerprints) ->
            pinned[host] = java.util.Collections.synchronizedSet(fingerprints.toMutableSet())
        }
    }

    /** Everything pinned, for a store to write. */
    val all: Map<String, Set<String>>
        get() = pinned.mapValues { it.value.toSet() }

    /** Whether this host has accepted this fingerprint. */
    fun accepts(fingerprint: String, host: String): Boolean =
        pinned[host]?.contains(fingerprint) == true

    /** Records an acceptance. Only ever called after a reader has seen the fingerprint. */
    fun pin(fingerprint: String, host: String) {
        pinned.getOrPut(host) { java.util.Collections.synchronizedSet(mutableSetOf()) }
            .add(fingerprint)
    }

    /** Forgets every pin for a host. Called when its source is removed. */
    fun forget(host: String) {
        pinned.remove(host)
    }
}

/** What a certificate says about itself, for the dialog that asks the reader. */
internal fun X509Certificate.described(host: String): UntrustedCertificate =
    UntrustedCertificate(
        host = host,
        fingerprint = java.security.MessageDigest.getInstance("SHA-256")
            .digest(encoded)
            // The same form `openssl x509 -fingerprint -sha256` prints, so a reader can
            // compare what the app shows against what their server told them without
            // transcribing either.
            .joinToString(":") { "%02X".format(it) },
        subject = subjectX500Principal.name ?: host,
        notValidAfter = notAfter,
    )
