package app.storyarc.core.kavita

import app.storyarc.core.model.KavitaHit
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

    /**
     * The routes this server has answered 404 to, so the discovery is paid for once.
     *
     * Held here because one client is one server. It lives for the session and no longer:
     * the answer is cheap to find again, and the registry of saved sources is a place for
     * what a reader chose rather than for what a server happened to answer.
     */
    private val unsupported = mutableSetOf<String>()

    /** What the server said about itself, once it has been asked. */
    var identity: KavitaIdentity? = null
        private set

    companion object {
        private const val TIMEOUT_MILLIS = 20_000

        /** The filter that asks a listing route for everything it holds. */
        private const val EMPTY_FILTER = "{}"

        /** The one status that means "this server does not have this route". */
        private const val NOT_FOUND = 404

        private val json = Json { ignoreUnknownKeys = true }
    }

    /**
     * Authenticates, and stops.
     *
     * One request, because the server answers only one question a plugin may ask: who is this
     * key. This used to ask a second, `Server/server-info`, to gate the server on a minimum
     * version. That route is in no shipped Kavita -- absent from the published `openapi.json`
     * of v0.8.6, v0.8.8, v0.8.9.1, v0.9.0 and v0.9.1.4, and 404 on a live 0.9.1.4 -- so the
     * 404 threw and **adding a Kavita source failed for every reader on every version**. The
     * gate it fed could never fire for the same reason.
     *
     * The gate was deleted rather than repaired on 2026-09-07, because nothing can feed it
     * and nothing would use it. No route states the version: `Server/version`,
     * `Health/api-version` and `Server/accepting-connections` all 404,
     * `Server/server-info-slim` is admin only, swagger is off in production, and `Health`
     * answers `Ok` with no version in it. And the verbs of every route either client calls
     * are identical across those five releases, which is April 2025 to September 2026, so a
     * version number would decide nothing.
     *
     * What replaces it is feature detection, which was already here: [listing] reads a 404 on
     * a listing route as that route missing, remembers it for the session, and says so in a
     * sentence. iOS's `KavitaClient.connect()` says the same.
     */
    suspend fun connect(): KavitaIdentity =
        KavitaIdentity(authenticate()).also { identity = it }

    /** The server's libraries. */
    suspend fun libraries(): List<KavitaLibraryFolder> =
        decode(get("Library/libraries"))

    /**
     * The series in one library, or in all of them.
     *
     * **The library is a statement in the body, not a query parameter.** Measured against a
     * live Kavita on 2026-09-06: `POST /api/Series/all-v2?libraryId=3` answered all 215
     * series across four libraries, so the parameter this client used to send did nothing at
     * all -- and the request succeeded, so a reader who picked one library was shown every
     * library and nothing reported a problem. The statement in [KavitaFilter] answered 91
     * series from library 3 alone. An empty filter is the whole list.
     *
     * A filter that cannot be encoded throws. It never widens to the whole server.
     */
    suspend fun series(libraryId: Int? = null): List<KavitaSeries> = decode(
        listing(
            "Series/all-v2",
            libraryId?.let {
                Json.encodeToString(KavitaFilter.serializer(), KavitaFilter.ofLibrary(it))
            } ?: EMPTY_FILTER,
        ),
    )

    /**
     * One series, asked for by identity.
     *
     * A search result names a series and the library it belongs to is not always in the
     * answer -- and Kavita keys progress by library *and* series, so opening a found series
     * without asking would report reading against library zero, which the server refuses.
     * One request on a tap, rather than a wrong write on every page turn afterwards.
     */
    suspend fun seriesDetail(id: Int): KavitaSeries = decode(get("Series/$id"))

    /**
     * The series a server added most recently, newest first, one page at a time.
     *
     * The library reads a server through this rather than through [series]: a server with
     * forty thousand series is minutes of requests and a cache nobody asked for, and what a
     * reader recognises on opening the app is what arrived last. `Series/recently-added-v2`
     * is a POST with a filter body, like every other Kavita listing, and it pages.
     */
    suspend fun recentSeries(page: Int = 1, size: Int = 20): List<KavitaSeries> = decode(
        listing("Series/recently-added-v2?pageNumber=$page&pageSize=$size", EMPTY_FILTER),
    )

    /** The volumes of one series, each with its chapters. */
    suspend fun volumes(seriesId: Int): List<KavitaVolume> =
        decode(get("Series/volumes", mapOf("seriesId" to seriesId.toString())))

    /**
     * One chapter's bytes, and what the server says they are.
     *
     * The media type comes back with them because a Kavita library holds comics and books
     * alike: writing every chapter to disk as `.cbz` sent an EPUB to the comic reader, which
     * spun for ever on a file it could not page.
     */
    suspend fun chapter(id: Int): KavitaFile {
        val answer = fetch(address.endpoint("Download/chapter", mapOf("chapterId" to id.toString())))
        return KavitaFile(answer.first, answer.second)
    }

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
     * A reading list's own cover, which a reader may have chosen on the server.
     *
     * Asked for only when the list says `coverImageLocked`. Otherwise the app composites the
     * list's first four entries itself, which is what `collections-and-reading-lists`
     * describes and what a local list shows beside it.
     */
    suspend fun readingListCover(id: Int): ByteArray = get(
        "Image/readinglist-cover",
        mapOf("readingListId" to id.toString(), "apiKey" to address.apiKey),
    )

    /**
     * A collection's own cover, which a reader may have chosen on the server.
     *
     * The twin of [readingListCover], and it had no twin until 2026-09-12: a collection could
     * not show a locked cover at all, because nothing asked for one. Kavita names the query
     * after the thing it belongs to, so this one is `collectionTagId` — the server calls a
     * collection a tag.
     */
    suspend fun collectionCover(id: Int): ByteArray = get(
        "Image/collection-cover",
        mapOf("collectionTagId" to id.toString(), "apiKey" to address.apiKey),
    )

    /**
     * Marks one chapter read or unread on the server.
     *
     * `kavita-server` asks for the state to be "reflected in that server's own UI", which a
     * position cannot do on its own: page zero of an unread chapter and page zero of a
     * chapter the reader deliberately unmarked are the same number.
     */
    suspend fun mark(seriesId: Int, chapterId: Int, isRead: Boolean) {
        val path = if (isRead) "Reader/mark-chapter-read" else "Reader/mark-chapter-unread"
        request(
            address.endpoint(path),
            method = "POST",
            body = Json.encodeToString(
                KavitaMark.serializer(),
                KavitaMark(seriesId = seriesId, chapterId = chapterId),
            ),
        )
    }

    /**
     * The chapter the reader should open next in a series.
     *
     * Asked of the server rather than worked out from the chapter list: Kavita knows what
     * other devices have read, and this app may not have pulled that yet.
     */
    suspend fun continuePoint(seriesId: Int): KavitaChapter =
        decode(get("Reader/continue-point", mapOf("seriesId" to seriesId.toString())))

    /**
     * Tells the server where the reader got to.
     *
     * `kavita-server`: the page position is sent "when a user reads a Kavita publication and
     * leaves the reader". Kavita wants the whole chain rather than the chapter alone, because
     * its own progress rows are keyed by all of it.
     */
    suspend fun report(progress: KavitaPosition) {
        request(
            address.endpoint("Reader/progress"),
            method = "POST",
            body = Json.encodeToString(KavitaPosition.serializer(), progress),
        )
    }

    /** What the server holds about a series, which the spec prefers over the file's own. */
    suspend fun metadata(seriesId: Int): KavitaMetadata =
        decode(get("Series/metadata", mapOf("seriesId" to seriesId.toString())))

    /** The collections this server holds. */
    suspend fun collections(): List<KavitaCollection> = decode(get("Collection"))

    /**
     * The series in one collection.
     *
     * `Series/series-by-collection`, which is the route Kavita publishes. This asked
     * `Collection/series` until 2026-09-07, a route in no shipped Kavita: absent from the
     * published `openapi.json` of v0.8.6, v0.8.8, v0.8.9.1, v0.9.0 and v0.9.1.4, and 404 on a
     * live 0.9.1.4, so no reader ever saw a collection's contents.
     *
     * `Collection/all-series` is not the replacement. Its parameters are `seriesId` and
     * `ownedOnly`, so it answers which collections hold one series -- the other question.
     */
    suspend fun collected(id: Int): List<KavitaSeries> =
        decode(get("Series/series-by-collection", mapOf("collectionId" to id.toString())))

    /**
     * The reading lists this server holds.
     *
     * A POST carrying a filter, for the reason [series] gives: measured against a live server
     * on 2026-09-06, a GET here is a 404 and this client sent one, so a reader who added their
     * own Kavita was shown no reading lists at all.
     */
    suspend fun readingLists(): List<KavitaReadingList> =
        decode(listing("ReadingList/lists", EMPTY_FILTER))

    /** One reading list's entries, in the order the server keeps. */
    suspend fun readingListItems(id: Int): List<KavitaReadingListItem> =
        decode(get("ReadingList/items", mapOf("readingListId" to id.toString())))

    /**
     * Appends chapters to a server reading list.
     *
     * `kavita-server` requires the change to be "reflected for other Kavita clients", which
     * is what sending it rather than keeping it locally buys.
     */
    suspend fun append(listId: Int, seriesId: Int, chapterIds: List<Int>) {
        request(
            address.endpoint("ReadingList/update-by-multiple"),
            method = "POST",
            body = Json.encodeToString(
                KavitaListAppend.serializer(),
                KavitaListAppend(listId, seriesId, chapterIds),
            ),
        )
    }

    /**
     * Makes a collection on the server and answers with what it became.
     *
     * `collections-and-reading-lists` lets a reader keep a new collection "on a server if the
     * user chooses one that supports collections". Kavita has no create route for a
     * collection: it brings one into being by tagging series, with a zero id meaning "make
     * it". So the create is a bulk-add, and the id has to be read back afterwards -- the
     * bulk-add answers with nothing, and everything a caller does next is addressed by the id
     * the server minted. The listing is read on both sides of the create so the new id can be
     * told from one the server already held under the same name.
     *
     * **A collection holding no series has never been made against a live Kavita.** The mock
     * takes one; a real server may not, because a collection with nothing in it is not a
     * thing Kavita's own interface can make. That is a live-server question, and
     * `docs/openspec/STATUS.md` scores it as one.
     */
    suspend fun createCollection(title: String, seriesIds: List<Int> = emptyList()): KavitaCollection {
        val before = collections().map { it.id }.toSet()
        request(
            address.endpoint("Collection/update-for-series"),
            method = "POST",
            body = Json.encodeToString(
                KavitaCollectionDraft.serializer(),
                KavitaCollectionDraft(0, title, seriesIds),
            ),
        )
        // By id rather than by name. Kavita lists collections by title, so a server that
        // already held one of this name lists two in no reliable order, and the last of them
        // can be the one somebody else made. One of that name is unambiguous either way.
        val named = collections().filter { it.title == title }
        return named.firstOrNull { it.id !in before }
            ?: named.singleOrNull()
            ?: throw KavitaError.UnexpectedResponse
    }

    /**
     * Moves one entry of a server reading list to a new place in it.
     *
     * `collections-and-reading-lists` makes a reading list's order its meaning, and asks for
     * a new order to be "sent to the server" for a server-backed list. Kavita moves one entry
     * at a time, by position rather than by identity, so a caller that wants a whole order
     * sends a run of these -- see `ShelfSync`, which plans that run.
     */
    suspend fun moveInList(listId: Int, item: Int, from: Int, to: Int) {
        request(
            address.endpoint("ReadingList/update-position"),
            method = "POST",
            body = Json.encodeToString(
                KavitaListPosition.serializer(),
                KavitaListPosition(listId, item, from, to),
            ),
        )
    }

    /**
     * Makes a new, empty reading list on the server and answers with what it became.
     *
     * `collections-and-reading-lists` lets a reader put a local list "on a server" so it
     * syncs and is visible elsewhere. The server mints the id, which is why this answers with
     * the list rather than with nothing: everything that follows -- the entries, and the
     * undo -- is addressed by it.
     */
    suspend fun createList(title: String): KavitaReadingList = decode(
        request(
            address.endpoint("ReadingList/create"),
            method = "POST",
            body = Json.encodeToString(KavitaListDraft.serializer(), KavitaListDraft(title)),
        ),
    )

    /**
     * Removes a reading list from the server.
     *
     * Here so the copy is reversible: `collections-and-reading-lists` makes every action of
     * this shape "undoable for 10 seconds", and the only way to take back a list the server
     * now holds is to ask the server to drop it again.
     */
    suspend fun deleteList(id: Int) {
        request(
            address.endpoint("ReadingList", mapOf("readingListId" to id.toString())),
            method = "DELETE",
        )
    }

    /**
     * Everything the server matched, in the five kinds the spec names.
     *
     * `kavita-server`: searching within a Kavita source sends the query to the server,
     * "returning matches across series, chapters, people, genres, and tags -- not only titles
     * cached locally". The comment this replaced said only the series half was read because
     * the rest "needs screens that do not exist yet" -- the screen exists now, so the rest is
     * read.
     *
     * Genres and tags arrive as one kind, for the reason `KavitaHit.Kind.SUBJECT` gives. A
     * person and a subject carry no series, because Kavita answers them with a name alone.
     */
    suspend fun find(query: String): List<KavitaHit> {
        val found = results(query)
        return found.series.map { KavitaHit(KavitaHit.Kind.SERIES, it.name, it.id) } +
            found.chapters.map {
                // The chapter's own identity, because two chapters of one series can be
                // named alike -- both untitled and both unnumbered read the same -- and a
                // keyed list refuses two rows with one key.
                KavitaHit(KavitaHit.Kind.CHAPTER, it.displayName, it.seriesId, chapterId = it.id)
            } +
            found.persons.map { KavitaHit(KavitaHit.Kind.PERSON, it.label) } +
            (found.genres + found.tags).map { KavitaHit(KavitaHit.Kind.SUBJECT, it.label) }
    }

    private suspend fun results(query: String): KavitaSearchResults =
        decode(get("Search/search", mapOf("queryString" to query)))

    /**
     * Posts to a listing route an older Kavita may not have, and remembers a 404.
     *
     * **A client cannot ask a Kavita what version it is.** Measured on 2026-09-06:
     * `/api/Server/version`, `/api/Health/api-version` and `/api/Server/accepting-connections`
     * all answer 404, `/api/Server/server-info-slim` is admin only, and swagger is off in
     * production. So feature detection is the only detection there is, and the feature is the
     * route answering at all.
     *
     * **Only a 404 counts.** A 401, a 403, a 500 or a timeout is the key or the server being
     * wrong for a moment. Reading one of those as "old server" would turn one expired token
     * into a permanent downgrade that no later good answer could undo. A 404 from the token
     * route is not counted either: [authenticate] names that route before the error travels.
     *
     * **There is no older shape to fall back to.** No documented v1 of these routes was
     * found, and Kavita's controllers carry no `[Obsolete]` marker naming one. Inventing a
     * request shape would be a guess a reader pays for, so this refuses in a sentence the
     * screens can draw instead. iOS's `KavitaClient.sendVersioned` does the same.
     */
    private suspend fun listing(path: String, body: String): ByteArray {
        if (path in unsupported) throw KavitaError.RouteMissing(path)
        try {
            return request(address.endpoint(path), method = "POST", body = body)
        } catch (refused: KavitaError.Http) {
            if (refused.status != NOT_FOUND) throw refused
            unsupported += path
            throw KavitaError.RouteMissing(path)
        }
    }

    private inline fun <reified T> decode(body: ByteArray): T =
        runCatching { json.decodeFromString<T>(String(body)) }
            .getOrElse { throw KavitaError.UnexpectedResponse }

    private suspend fun authenticate(): String {
        val url = address.endpoint(
            "Plugin/authenticate",
            mapOf("apiKey" to address.apiKey, "pluginName" to "StoryArc"),
        )
        // A 404 here is this route missing, not whichever route the caller wanted. Letting it
        // travel outwards lets [listing] record it against a listing the reader never reached,
        // and that listing then refuses for the rest of the session.
        val body = try {
            request(url, method = "POST", authenticated = false)
        } catch (refused: KavitaError.Http) {
            if (refused.status != NOT_FOUND) throw refused
            throw KavitaError.RouteMissing("Plugin/authenticate")
        }
        val account = runCatching { json.decodeFromString<KavitaAccount>(String(body)) }
            .getOrElse { throw KavitaError.UnexpectedResponse }
        token = account.token
        return account.username
    }

    /** One GET against an endpoint, as bytes. */
    suspend fun get(path: String, query: Map<String, String> = emptyMap()): ByteArray =
        request(address.endpoint(path, query))

    /** The same, keeping the media type the server declared. */
    private suspend fun fetch(url: String): Pair<ByteArray, String?> {
        var type: String? = null
        val body = request(url) { type = it }
        return body to type
    }

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
        body: String? = null,
        onType: ((String?) -> Unit)? = null,
    ): ByteArray {
        if (authenticated && token == null) authenticate()
        val first = attempt(url, method, if (authenticated) token else null, body)
        if (first.status != 401 || !authenticated) {
            onType?.invoke(first.type)
            return first.orThrow()
        }

        token = null
        authenticate()
        val retried = attempt(url, method, token, body)
        // Still refused after a fresh token: the key itself is no longer valid.
        if (retried.status == 401) throw KavitaError.KeyRejected
        onType?.invoke(retried.type)
        return retried.orThrow()
    }

    private class Answer(val status: Int, val body: ByteArray, val type: String? = null) {
        fun orThrow(): ByteArray = when {
            status == 401 -> throw KavitaError.KeyRejected
            status in 200..299 -> body
            else -> throw KavitaError.Http(status)
        }
    }

    private suspend fun attempt(
        url: String,
        method: String,
        bearer: String?,
        body: String? = null,
    ): Answer =
        withContext(Dispatchers.IO) {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.requestMethod = method
            connection.connectTimeout = TIMEOUT_MILLIS
            connection.readTimeout = TIMEOUT_MILLIS
            connection.useCaches = false
            connection.setRequestProperty("Accept", "application/json")
            bearer?.let { connection.setRequestProperty("Authorization", "Bearer $it") }
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(body.toByteArray()) }
            }
            try {
                val status = connection.responseCode
                val stream = if (status in 200..299) {
                    connection.inputStream
                } else {
                    connection.errorStream
                }
                Answer(
                    status,
                    stream?.use { it.readBytes() } ?: ByteArray(0),
                    connection.contentType?.substringBefore(';')?.trim(),
                )
            } finally {
                connection.disconnect()
            }
        }
}

/**
 * Who the reader is on this server, which is all authentication answers with.
 *
 * It held a version until 2026-09-07. Nothing could fill that field: no route on any shipped
 * Kavita states the server's version to a plugin. See [KavitaClient.connect].
 */
data class KavitaIdentity(val username: String)

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

    /**
     * The server does not have this route, so it is an older Kavita than this app can use.
     *
     * The only signal there is. Nothing states a version: see [KavitaClient.connect] and
     * `KavitaClient.listing`.
     */
    data class RouteMissing(val path: String) : KavitaError("no route $path")

    data class Http(val status: Int) : KavitaError("http $status")
}

/** What `Plugin/authenticate` returns. */
@Serializable
internal data class KavitaAccount(val username: String, val token: String)

/**
 * What `Search/search` returns, of what this app reads.
 *
 * Every list defaults to empty. Kavita omits the kinds a query matched nothing in, and a
 * decoder that insisted on all five would turn every narrow search into "unexpected
 * response".
 */
@Serializable
internal data class KavitaSearchResults(
    val series: List<KavitaSeries> = emptyList(),
    val chapters: List<KavitaChapter> = emptyList(),
    /** Kavita's own spelling. Called people everywhere else in this app. */
    val persons: List<KavitaNamed> = emptyList(),
    val genres: List<KavitaNamed> = emptyList(),
    val tags: List<KavitaNamed> = emptyList(),
)
