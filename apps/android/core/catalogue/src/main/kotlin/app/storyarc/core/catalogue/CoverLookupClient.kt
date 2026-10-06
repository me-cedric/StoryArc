package app.storyarc.core.catalogue

import app.storyarc.core.model.CoverIdentifier
import app.storyarc.core.model.CoverImageHosts
import app.storyarc.core.model.CoverLookupRequest
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** One request a cover lookup makes, which is the whole of what it sends. */
data class CoverFetch(
    val url: String,
    val method: String = "GET",
    val accept: String = "application/json",
    val body: String? = null,
)

/** What a provider answered, and the address the answer ended at after any redirect. */
data class CoverFetched(val status: Int, val body: ByteArray, val url: String) {
    // Generated equality would compare the array by identity, which is never what a caller
    // means. Declared rather than left to the data class, because the compiler warns.
    override fun equals(other: Any?): Boolean =
        other is CoverFetched &&
            status == other.status &&
            url == other.url &&
            body.contentEquals(other.body)

    override fun hashCode(): Int = (status * 31 + url.hashCode()) * 31 + body.contentHashCode()
}

/**
 * How a cover request reaches the network.
 *
 * A seam rather than a direct call, so a test can assert what was sent -- and, for task 3.5,
 * assert that nothing was. `HttpURLConnection` rather than a new dependency, for the reason
 * `OpdsClient` gives: the app makes one kind of request and the platform already makes it.
 */
fun interface CoverTransport {
    /** The answer, or null when nothing answered at all. */
    suspend fun send(request: CoverFetch): CoverFetched?
}

/** The transport the app uses, which is the platform's own. */
object PlatformCoverTransport : CoverTransport {
    private const val TIMEOUT_MILLIS = 15_000

    /** The largest answer read. A cover is not 8 MB, and an answer is untrusted input. */
    const val MAX_BYTES = 8 * 1024 * 1024

    private const val MAX_REDIRECTS = 5

    override suspend fun send(request: CoverFetch): CoverFetched? = withContext(Dispatchers.IO) {
        // Redirects are followed here, one at a time, and only to a listed host. Followed by
        // the connection, a redirect would reach whatever host it named before anything
        // could look at it.
        var current = request
        repeat(MAX_REDIRECTS + 1) {
            if (!CoverImageHosts.allows(current.url)) return@withContext null
            val answered = once(current) ?: return@withContext null
            val next = answered.redirect ?: return@withContext answered.fetched
            current = CoverFetch(URL(URL(current.url), next).toString(), accept = request.accept)
        }
        null
    }

    private class Answered(val fetched: CoverFetched?, val redirect: String?)

    private fun once(request: CoverFetch): Answered? =
        runCatching {
            val connection = URL(request.url).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.requestMethod = request.method
            connection.connectTimeout = TIMEOUT_MILLIS
            connection.readTimeout = TIMEOUT_MILLIS
            // Nothing cached by the connection: the client below keeps its own record of
            // every answer, and a second cache with a different lifetime would re-ask a
            // provider the first one had already decided was done with.
            connection.useCaches = false
            connection.setRequestProperty("Accept", request.accept)
            request.body?.let {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { stream -> stream.write(it.toByteArray()) }
            }
            try {
                val status = connection.responseCode
                if (status in 300..399) {
                    return@runCatching Answered(null, connection.getHeaderField("Location"))
                }
                val stream =
                    if (status in 200..299) connection.inputStream else connection.errorStream
                val body = stream?.use { it.readAtMost(MAX_BYTES) } ?: ByteArray(0)
                Answered(CoverFetched(status, body, request.url), redirect = null)
            } finally {
                connection.disconnect()
            }
        }.getOrNull()

    /** The stream's bytes; an answer over [limit] throws, and the caller reads that as none. */
    private fun InputStream.readAtMost(limit: Int): ByteArray {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val read = read(buffer)
            if (read < 0) return out.toByteArray()
            check(out.size() + read <= limit) { "answer over $limit bytes" }
            out.write(buffer, 0, read)
        }
    }
}

/**
 * Asks an open catalogue where one publication's cover is, when the reader has said it may.
 *
 * Three rules shape every method here, and all three are `cover-art` requirements rather
 * than taste:
 *
 * 1. **Nothing is asked while the setting is off.** The gate is the first statement of
 *    [cover], before an address is even built, so there is no path through this type that
 *    reaches the network without it.
 * 2. **One request per publication.** The cache is consulted first and written after, and a
 *    recorded refusal counts as an answer.
 * 3. **A refusal is quiet.** Nothing throws. A reader who did not ask for this cover is
 *    shown no error about it, and nothing retries.
 *
 * iOS's `CoverLookupClient` keeps the same three rules.
 */
class CoverLookupClient(
    /**
     * Whether the reader has turned the lookup on, read at the moment of use.
     *
     * A function rather than a stored flag: the setting can change while the app runs, and a
     * copy taken at construction would let a reader switch the lookup off and still be asked
     * about by whichever client was already made.
     */
    internal val isEnabled: () -> Boolean,
    internal val cache: CoverLookupCache,
    internal val transport: CoverTransport = PlatformCoverTransport,
) {
    private companion object {
        val json = Json { ignoreUnknownKeys = true }
    }

    /**
     * Where this publication's cover is, or null.
     *
     * `key` identifies the publication for the cache only. It never travels: the request is
     * built from `identifier` and from nothing else, which is what `cover-art` means by "no
     * library listing, no reading history, no device identifier".
     */
    suspend fun cover(key: String, identifier: CoverIdentifier): String? = lookUp(key, identifier)?.url

    /**
     * The looked-up cover's picture, or null. One call for the ladder: the lookup, then the
     * picture. An image provider already answered with the picture, so it is not asked twice.
     */
    suspend fun coverImage(key: String, identifier: CoverIdentifier): ByteArray? {
        val found = lookUp(key, identifier) ?: return null
        return found.picture ?: image(found.url)
    }

    /**
     * The picture at [url], or null. Only behind the setting, only from a listed host, and
     * never more than [PlatformCoverTransport.MAX_BYTES].
     */
    suspend fun image(url: String): ByteArray? {
        if (!isEnabled() || !CoverImageHosts.allows(url)) return null
        val answered = transport.send(CoverFetch(url, accept = "image/*")) ?: return null
        return answered.body.takeIf { answered.status in 200..299 && it.isNotEmpty() }
    }

    private class Found(val url: String, val picture: ByteArray?)

    private suspend fun lookUp(key: String, identifier: CoverIdentifier): Found? {
        if (!isEnabled()) return null
        cache.answer(key)?.let { answer -> return answer.imageUrl?.let { Found(it, null) } }

        val found = ask(identifier)
        cache.record(CoverLookupAnswer(identifier.provider, found?.url), key)
        return found
    }

    /**
     * One request, and whatever it answers.
     *
     * A 403, a 404, a 429 or no answer at all all come back as null. They are different
     * reasons for the same outcome -- this publication keeps the cover it had -- and telling
     * them apart here would only create somewhere for a retry to be added later.
     */
    private suspend fun ask(identifier: CoverIdentifier): Found? {
        val provider = identifier.provider
        val answered = transport.send(
            CoverFetch(
                url = CoverLookupRequest.url(identifier),
                accept = if (provider.answersWithImage) "image/*" else "application/json",
            ),
        ) ?: return null
        if (answered.status !in 200..299) return null

        // Both image providers answer the picture at the address that was asked for, after
        // whatever redirects they use. The address the transport ended on is the one to
        // keep: the Cover Art Archive's front route is a redirect to an Internet Archive
        // file, and storing the redirect rather than its target would ask twice on every
        // read.
        if (provider.answersWithImage) return Found(answered.url, answered.body)
        return imageUrlInBookDocument(answered.body)?.let { Found(it, null) }
    }

    /**
     * The `image` field of an Audnexus book document.
     *
     * The one provider that answers with a document rather than a picture. Read without a
     * model type because one field is wanted: a class would state nine more and break the
     * day the service adds a tenth.
     */
    internal fun imageUrlInBookDocument(body: ByteArray): String? = runCatching {
        json.parseToJsonElement(String(body)).jsonObject["image"]?.jsonPrimitive?.contentOrNull
    }.getOrNull()?.takeIf(CoverImageHosts::allows)
}
