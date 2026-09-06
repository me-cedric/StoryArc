package app.storyarc.core.catalogue

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLHandshakeException
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
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
     * A publication, written to [into] and resumed from whatever [into] already holds.
     *
     * Separate from [bytes] because the two want different things of one body. A cover or a
     * feed is small and is parsed in memory; a publication is the 400 MB comic
     * `offline-downloads` names in its purpose, and holding that in a `ByteArray` is what
     * made a download an allocation the size of the file.
     *
     * `offline-downloads`' *Resuming after interruption*: an interrupted download "resumes
     * from where it stopped if the server supports range requests, and restarts otherwise".
     * [into] is the partial file, so its length is the offset to ask from -- but only when a
     * validator was recorded beside it, because only the validator makes the server say
     * whether the bytes on disk are still a prefix of what it holds. See [resumable].
     *
     * There are two answers to that ask, and only one of them continues the file:
     *
     * - **206.** The server compared the validator, and gave the rest. The bytes are appended.
     * - **Anything else.** The server would not continue this file. It may be sending the
     *   whole resource, which RFC 9110 permits, or only the requested window while saying
     *   200, which `scripts/opds-server.mjs` sends as `?lie=status` -- and the headers do not
     *   tell the two apart, because `Content-Length` describes whichever one it sent. So the
     *   body is not read at all: the partial is dropped and the file is asked for again with
     *   no `Range`, which is a first attempt and is checked as one. A 416 says the same
     *   thing in its own words and takes the same path.
     */
    suspend fun download(url: String, credential: OpdsCredential? = null, into: File) {
        try {
            fetch(url, credential, into, resuming = resumable(into))
        } catch (restart: Restart) {
            fetch(url, credential, into, resuming = null)
        }
        // A cancelled copy stops mid-body and leaves the bytes it wrote, which is the point:
        // the next attempt asks for the rest of them. It is not a completed download, so the
        // caller has to be told cancellation rather than handed a short file to index.
        coroutineContext.ensureActive()
    }

    /**
     * What the last attempt recorded of the resource [into] holds a prefix of, or null.
     *
     * Null means *do not resume*. A `Range` sent without an `If-Range` asks a server to
     * continue a file it has no way to check: a publication re-served at the same address
     * after a re-scan or a re-compression answers 206 for a prefix that is no longer its own,
     * the two builds splice, and the result is a file of exactly the declared length whose
     * first half is unreadable. Nothing downstream can catch that -- the length is right, and
     * the index reads a central directory that is intact -- so it is refused here instead.
     * `offline-downloads` names the fallback in the same sentence: it "restarts otherwise".
     */
    private fun resumable(into: File): String? {
        if (!into.isFile || into.length() == 0L) return null
        val tag = File(into.path + TAG_SUFFIX)
        return if (tag.isFile) tag.readText().takeIf { it.isNotBlank() } else null
    }

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
    private suspend fun fetch(
        url: String,
        credential: OpdsCredential?,
        into: File? = null,
        resuming: String? = null,
    ): Fetched =
        withContext(Dispatchers.IO) {
            // Read once, outside the blocking read loop. A copy that runs after the caller
            // gave up spends the bytes the pause exists to save.
            val job = coroutineContext[Job]
            // The configured source's origin, or -- for an address the reader typed, which
            // has nothing to be compared against -- its own.
            val home = origin ?: OpdsOrigin.of(url)
            // Tied to the validator rather than read from the file on its own: bytes with
            // nothing to check them against are bytes this client starts over from.
            val from = if (resuming != null && into?.isFile == true) into.length() else 0L
            var target = url
            var hops = 0
            while (true) {
                val sink = into?.let { Sink(it, from, resuming) { job?.isActive != false } }
                when (val hop = one(target, credential, home, sink)) {
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

    /** Where a publication's bytes go, from which offset, and for as long as anyone wants them. */
    private class Sink(
        val into: File,
        val from: Long,
        val validator: String?,
        val keepGoing: () -> Boolean,
    ) {
        /** Beside the partial, and so inside the directory a removal deletes. */
        val tag: File = File(into.path + TAG_SUFFIX)
    }

    /**
     * The server would not carry this file on, so the download starts over.
     *
     * Thrown only for a request that carried a `Range`, and caught only by [download], whose
     * next attempt carries none -- so it cannot be thrown twice for one download. An
     * [IOException] rather than something of its own, so that a future gap in that reasoning
     * reaches the queue as a failed transfer rather than as a crash.
     */
    private class Restart : IOException("the server would not continue the file")

    private fun one(
        url: String,
        credential: OpdsCredential?,
        home: OpdsOrigin?,
        sink: Sink? = null,
    ): Hop {
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
        // Open-ended, because the app wants the rest of the file and not a window into it.
        // `If-Range` travels with it and is not optional: it is the whole of what makes the
        // server compare the prefix on disk against what it holds now, and answer with the
        // whole file instead of splicing a changed publication onto a stale half.
        val validator = sink?.validator
        if (sink != null && sink.from > 0 && validator != null) {
            connection.setRequestProperty("Range", "bytes=${sink.from}-")
            connection.setRequestProperty("If-Range", validator)
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
                // The bytes asked for are not there, so what is on disk is not a prefix of
                // the file and there is nothing to carry on from.
                status == RANGE_NOT_SATISFIABLE && sink != null && sink.from > 0 -> throw Restart()
                else -> throw OpdsError.Http(status)
            }

            if (sink != null) {
                // A ranged request answered by anything but 206 is not a continuation, and
                // the headers do not say what it is instead: a server sending the whole
                // resource and a server sending only the window both declare the length of
                // what they sent, so the second one's slice would pass every check this
                // client can make and land as a publication missing its opening bytes. The
                // body is left unread and the file asked for again with no range, which is
                // the one request whose length describes the whole publication.
                if (sink.from > 0 && status != HttpURLConnection.HTTP_PARTIAL) throw Restart()
                connection.inputStream.use { stream -> write(stream, connection, status, sink) }
                return Hop.Done(Fetched(ByteArray(0), connection.contentType, url))
            }

            val body = connection.inputStream.use { it.readBytes() }
            if (body.isEmpty()) throw OpdsError.Empty
            return Hop.Done(Fetched(body, connection.contentType, url))
        } finally {
            connection.disconnect()
        }
    }

    /**
     * The body onto disk, appended only when the server said it is a continuation.
     *
     * 206 is the one status whose bytes carry on from what is already there. Any other
     * success is the whole resource, including a 200 answering a request that carried a
     * `Range` -- RFC 9110 lets a server ignore a range it does not want to serve, and
     * `scripts/opds-server.mjs` does exactly that on request because real servers, proxies
     * and captive portals do. Appending that onto a prefix writes a longer file that is not
     * the publication.
     */
    private fun write(stream: InputStream, connection: HttpURLConnection, status: Int, sink: Sink) {
        val append = status == HttpURLConnection.HTTP_PARTIAL
        sink.into.parentFile?.mkdirs()
        // Recorded before the first byte lands, because the attempt that needs it is the one
        // after an interruption, and after an interruption there is no response left to read
        // it from.
        if (!append) record(connection, sink)
        FileOutputStream(sink.into, append).use { out ->
            val buffer = ByteArray(COPY_BYTES)
            while (sink.keepGoing()) {
                val read = stream.read(buffer)
                if (read < 0) break
                out.write(buffer, 0, read)
            }
        }
        if (!sink.keepGoing()) return
        if (sink.into.length() == 0L) throw OpdsError.Empty
        // What the server said the whole file weighs. A body that stopped early is a file
        // this app must not hand to the indexer as a finished download, and a short read
        // does not always raise on its own.
        val whole = declaredLength(connection, status)
        if (whole != null && sink.into.length() != whole) {
            throw IOException("the download stopped at ${sink.into.length()} of $whole bytes")
        }
        // The file is whole, so the validator that guarded its resumes is spent.
        sink.tag.delete()
    }

    /**
     * Keeps what the server says identifies this version of the resource, or keeps nothing.
     *
     * A weak `ETag` says two responses are equivalent, not identical, and RFC 9110 forbids
     * one in an `If-Range` for exactly the reason this app needs it: a prefix is bytes, and
     * equivalent bytes are not the same bytes. A server that offers neither a strong `ETag`
     * nor a `Last-Modified` leaves no file, and a download from it restarts rather than
     * resuming -- which is the other half of the sentence `offline-downloads` writes.
     */
    private fun record(connection: HttpURLConnection, sink: Sink) {
        val validator = connection.getHeaderField("ETag")?.takeIf { !it.startsWith("W/") }
            ?: connection.getHeaderField("Last-Modified")
        if (validator == null) sink.tag.delete() else sink.tag.writeText(validator)
    }

    /** What the response says the complete resource weighs, or null when it does not say. */
    private fun declaredLength(connection: HttpURLConnection, status: Int): Long? =
        if (status == HttpURLConnection.HTTP_PARTIAL) {
            connection.getHeaderField("Content-Range")?.substringAfterLast('/')?.toLongOrNull()
        } else {
            connection.getHeaderField("Content-Length")?.toLongOrNull()
        }

    private companion object {
        const val TIMEOUT_MILLIS = 20_000

        /** What a browser allows too. A server that needs more is looping. */
        const val MAX_REDIRECTS = 5

        /** One read of a publication being written to disk. */
        const val COPY_BYTES = 64 * 1024

        /** The bytes asked for are not there, so what is on disk is not a prefix of the file. */
        const val RANGE_NOT_SATISFIABLE = 416

        /** What is added to a partial file's name to name the validator kept beside it. */
        const val TAG_SUFFIX = ".tag"
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
