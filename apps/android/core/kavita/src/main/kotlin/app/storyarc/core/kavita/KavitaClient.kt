package app.storyarc.core.kavita

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * A Kavita server, and what StoryArc asks it.
 *
 * Kavita already speaks OPDS and a reader can add one as a catalogue today. This exists
 * because, as the spec puts it, "OPDS cannot express collections, reading lists, per-page
 * progress, or the 'want to read' state".
 *
 * **Built against Kavita's documented API and the mock in `scripts/kavita-server.mjs`, not
 * against a live server.** Nobody here has one. The first person to point this at a real
 * Kavita should expect to correct something, and the mock is where a correction gets
 * recorded. iOS's `KavitaClient` makes the same requests.
 */
class KavitaClient(val address: KavitaAddress) {

    /**
     * The session token, held only in memory.
     *
     * `kavita-server` requires the app to "manage session tokens without exposing them to
     * the user". Not persisted either: a token is short-lived, the API key that mints one is
     * what the secure store holds, and a stale token on disk is one more thing that can be
     * wrong on a cold launch.
     */
    private var token: String? = null

    /** What the server said about itself, once it has been asked. */
    var identity: KavitaIdentity? = null
        private set

    companion object {
        /**
         * The oldest Kavita this app knows how to talk to.
         *
         * `kavita-server` requires the app to reject an older server "naming the required
         * version", which is a better failure than a series list that is silently empty
         * because an endpoint moved.
         */
        val MINIMUM_VERSION = KavitaVersion(0, 8, 0)

        private const val TIMEOUT_MILLIS = 20_000
        private val json = Json { ignoreUnknownKeys = true }
    }

    /**
     * Authenticates, and reports what the server is.
     *
     * Two requests, because they answer two different questions: who am I, and what is this.
     * A reader whose key works against a server too old to use needs to be told the second.
     */
    suspend fun connect(): KavitaIdentity {
        val account = authenticate()
        val info = json.decodeFromString<KavitaServerInfo>(String(get("Server/server-info")))
        val version = KavitaVersion.of(info.kavitaVersion) ?: throw KavitaError.UnexpectedResponse
        if (version < MINIMUM_VERSION) {
            throw KavitaError.ServerTooOld(version, MINIMUM_VERSION)
        }
        return KavitaIdentity(account, version).also { identity = it }
    }

    /** The server's libraries. */
    suspend fun libraries(): List<KavitaLibraryFolder> =
        decode(get("Library/libraries"))

    /** The series in one library, or in all of them. */
    suspend fun series(libraryId: Int? = null): List<KavitaSeries> = decode(
        get("Series/all-v2", libraryId?.let { mapOf("libraryId" to it.toString()) } ?: emptyMap()),
    )

    /** The volumes of one series, each with its chapters. */
    suspend fun volumes(seriesId: Int): List<KavitaVolume> =
        decode(get("Series/volumes", mapOf("seriesId" to seriesId.toString())))

    /** One chapter's bytes. */
    suspend fun chapter(id: Int): ByteArray =
        get("Download/chapter", mapOf("chapterId" to id.toString()))

    /**
     * A series cover, as image bytes.
     *
     * Kavita's image routes take the key in the query rather than a bearer token, but this
     * goes through the same request path anyway: one place that knows how to reach the
     * server is easier to keep correct than two.
     */
    suspend fun seriesCover(id: Int): ByteArray = get(
        "Image/series-cover",
        mapOf("seriesId" to id.toString(), "apiKey" to address.apiKey),
    )

    /** A chapter cover, as image bytes. */
    suspend fun chapterCover(id: Int): ByteArray = get(
        "Image/chapter-cover",
        mapOf("chapterId" to id.toString(), "apiKey" to address.apiKey),
    )

    /**
     * The chapter the reader should open next in a series.
     *
     * Asked of the server rather than worked out from the chapter list: Kavita knows what
     * other devices have read, and this app may not have pulled that yet.
     */
    suspend fun continuePoint(seriesId: Int): KavitaChapter =
        decode(get("Reader/continue-point", mapOf("seriesId" to seriesId.toString())))

    /** What the server holds about a series, which the spec prefers over the file's own. */
    suspend fun metadata(seriesId: Int): KavitaMetadata =
        decode(get("Series/metadata", mapOf("seriesId" to seriesId.toString())))

    /**
     * Series matching a query, answered by the server.
     *
     * Only the series half is read. The rest of what Kavita returns -- chapters, people,
     * genres, tags -- needs screens that do not exist yet, and decoding fields nothing shows
     * would be pretending.
     */
    suspend fun search(query: String): List<KavitaSeries> =
        decode<KavitaSearchResults>(get("Search/search", mapOf("queryString" to query))).series

    private inline fun <reified T> decode(body: ByteArray): T =
        runCatching { json.decodeFromString<T>(String(body)) }
            .getOrElse { throw KavitaError.UnexpectedResponse }

    private suspend fun authenticate(): String {
        val url = address.endpoint(
            "Plugin/authenticate",
            mapOf("apiKey" to address.apiKey, "pluginName" to "StoryArc"),
        )
        val body = request(url, method = "POST", authenticated = false)
        val account = runCatching { json.decodeFromString<KavitaAccount>(String(body)) }
            .getOrElse { throw KavitaError.UnexpectedResponse }
        token = account.token
        return account.username
    }

    /** One GET against an endpoint, as bytes. */
    suspend fun get(path: String, query: Map<String, String> = emptyMap()): ByteArray =
        request(address.endpoint(path, query))

    /**
     * One request, re-authenticating once if the token has expired.
     *
     * `kavita-server`: when a token expires "the app re-authenticates with the stored API key
     * and retries the request once, without the user seeing an error". Once, not in a loop: a
     * server that answers 401 to a freshly minted token is saying the key is gone, and
     * retrying for ever would hide that.
     */
    private suspend fun request(
        url: String,
        method: String = "GET",
        authenticated: Boolean = true,
    ): ByteArray {
        if (authenticated && token == null) authenticate()
        val first = attempt(url, method, if (authenticated) token else null)
        if (first.status != 401 || !authenticated) return first.orThrow()

        token = null
        authenticate()
        val retried = attempt(url, method, token)
        // Still refused after a fresh token: the key itself is no longer valid.
        if (retried.status == 401) throw KavitaError.KeyRejected
        return retried.orThrow()
    }

    private class Answer(val status: Int, val body: ByteArray) {
        fun orThrow(): ByteArray = when {
            status == 401 -> throw KavitaError.KeyRejected
            status in 200..299 -> body
            else -> throw KavitaError.Http(status)
        }
    }

    private suspend fun attempt(url: String, method: String, bearer: String?): Answer =
        withContext(Dispatchers.IO) {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.requestMethod = method
            connection.connectTimeout = TIMEOUT_MILLIS
            connection.readTimeout = TIMEOUT_MILLIS
            connection.useCaches = false
            connection.setRequestProperty("Accept", "application/json")
            bearer?.let { connection.setRequestProperty("Authorization", "Bearer $it") }
            try {
                val status = connection.responseCode
                val stream = if (status in 200..299) {
                    connection.inputStream
                } else {
                    connection.errorStream
                }
                Answer(status, stream?.use { it.readBytes() } ?: ByteArray(0))
            } finally {
                connection.disconnect()
            }
        }
}

/** What a server says it is, once it has answered. */
data class KavitaIdentity(val username: String, val version: KavitaVersion)

/** A Kavita version, compared the way versions are compared rather than as a string. */
data class KavitaVersion(val major: Int, val minor: Int, val patch: Int) :
    Comparable<KavitaVersion> {

    override fun compareTo(other: KavitaVersion): Int = compareValuesBy(
        this,
        other,
        { it.major },
        { it.minor },
        { it.patch },
    )

    override fun toString(): String = "$major.$minor.$patch"

    companion object {
        /**
         * Reads `0.8.3` or `0.8.3.2`, which Kavita has used both of.
         *
         * A fourth component is ignored rather than refused: it is a build number, and a
         * server that reports one is not a server this app should decline to talk to.
         */
        fun of(text: String): KavitaVersion? {
            val parts = text.split(".").mapNotNull { it.toIntOrNull() }
            if (parts.size < 2) return null
            return KavitaVersion(parts[0], parts[1], parts.getOrElse(2) { 0 })
        }
    }
}

/** Why a Kavita server did not answer the way it should. */
sealed class KavitaError(message: String) : IOException(message) {
    data object BadAddress : KavitaError("bad address") {
        private fun readResolve(): Any = BadAddress
    }

    data object UnexpectedResponse : KavitaError("unexpected response") {
        private fun readResolve(): Any = UnexpectedResponse
    }

    /**
     * The API key is no longer valid. `kavita-server`: the source is marked `unauthorized`
     * "with an explanation and an action to enter a new key".
     */
    data object KeyRejected : KavitaError("api key rejected") {
        private fun readResolve(): Any = KeyRejected
    }

    /** Older than this app knows how to talk to, named so the reader can act. */
    data class ServerTooOld(val found: KavitaVersion, val required: KavitaVersion) :
        KavitaError("kavita $found is older than $required")

    data class Http(val status: Int) : KavitaError("http $status")
}

/** What `Plugin/authenticate` returns. */
@Serializable
internal data class KavitaAccount(val username: String, val token: String)

/** What `Server/server-info` returns, of what this app reads. */
@Serializable
internal data class KavitaServerInfo(val kavitaVersion: String)

/** What `Search/search` returns, of what this app reads. */
@Serializable
internal data class KavitaSearchResults(val series: List<KavitaSeries> = emptyList())
