package app.storyarc.core.catalogue

import app.storyarc.core.model.CoverIdentifier
import app.storyarc.core.model.CoverLookupRequest
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
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

    override suspend fun send(request: CoverFetch): CoverFetched? = withContext(Dispatchers.IO) {
        runCatching {
            val connection = URL(request.url).openConnection() as HttpURLConnection
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
                val stream =
                    if (status in 200..299) connection.inputStream else connection.errorStream
                CoverFetched(
                    status,
                    stream?.use { it.readBytes() } ?: ByteArray(0),
                    connection.url.toString(),
                )
            } finally {
                connection.disconnect()
            }
        }.getOrNull()
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
    private val cache: CoverLookupCache,
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
    suspend fun cover(key: String, identifier: CoverIdentifier): String? {
        if (!isEnabled()) return null
        cache.answer(key)?.let { return it.imageUrl }

        val found = ask(identifier)
        cache.record(CoverLookupAnswer(identifier.provider, found), key)
        return found
    }

    /**
     * One request, and whatever it answers.
     *
     * A 403, a 404, a 429 or no answer at all all come back as null. They are different
     * reasons for the same outcome -- this publication keeps the cover it had -- and telling
     * them apart here would only create somewhere for a retry to be added later.
     */
    private suspend fun ask(identifier: CoverIdentifier): String? {
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
        if (provider.answersWithImage) return answered.url
        return imageUrlInBookDocument(answered.body)
    }

    /**
     * The `image` field of an Audnexus book document.
     *
     * The one provider that answers with a document rather than a picture. Read without a
     * model type because one field is wanted: a class would state nine more and break the
     * day the service adds a tenth.
     */
    internal fun imageUrlInBookDocument(body: ByteArray): String? = runCatching {
        json.parseToJsonElement(String(body)).jsonObject["image"]?.jsonPrimitive?.content
    }.getOrNull()
}
