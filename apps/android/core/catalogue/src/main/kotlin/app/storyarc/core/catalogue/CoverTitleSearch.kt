package app.storyarc.core.catalogue

import app.storyarc.core.model.CoverImageHosts
import java.net.URLEncoder
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/**
 * A keyless catalogue that answers a title with candidates.
 *
 * Separate from `CoverLookupProvider` because these answer a question with several answers
 * and that one answers a question with one. Joining them would give the exact lookup a
 * "which of these did you mean" that it never has.
 */
enum class CoverTitleProvider {
    /** Books, by title and author. */
    OPEN_LIBRARY,

    /** Manga and anime. Keyless, and the one most likely to know a volume by its series. */
    ANILIST,

    /** Manga, including many series AniList has no entry for. */
    MANGA_UPDATES,
    ;

    val displayName: String
        get() = when (this) {
            OPEN_LIBRARY -> "Open Library"
            ANILIST -> "AniList"
            MANGA_UPDATES -> "MangaUpdates"
        }

    val host: String
        get() = when (this) {
            OPEN_LIBRARY -> "openlibrary.org"
            ANILIST -> "graphql.anilist.co"
            MANGA_UPDATES -> "api.mangaupdates.com"
        }
}

/**
 * A cover a title search found, which a reader may accept or ignore.
 *
 * `cover-art`: the app "SHALL show the candidates and let the reader choose", and "never
 * silently adopts a match it is not certain of, because a wrong cover is worse than none".
 * So this type is what a search returns -- never what a search applies.
 */
@Serializable
data class CoverCandidate(
    /** The title the catalogue holds, which is what a reader compares against their file. */
    val title: String,
    val imageUrl: String,
    val provider: CoverTitleProvider,
    /**
     * The author or the year, when the catalogue stated one. Null rather than an empty
     * string, so a row draws one line instead of a blank second one.
     */
    val subtitle: String? = null,
)

/**
 * How a title is asked about, and how each answer is read.
 *
 * Every function here is pure, so the three request shapes and the three response shapes are
 * asserted without a socket. iOS's `CoverTitleSearch` builds and reads the same three.
 */
object CoverTitleSearch {
    private val json = Json { ignoreUnknownKeys = true }

    /**
     * The AniList query, which asks for the one field a candidate needs from each match.
     *
     * `perPage: 10` because a reader chooses from a list they can read. A longer list is a
     * longer scroll through covers that are all nearly right.
     */
    internal const val ANILIST_QUERY =
        "query (\$search: String) { Page(perPage: 10) { media(search: \$search, type: MANGA) " +
            "{ title { romaji english } coverImage { large } } } }"

    /**
     * The request that asks one provider about one title.
     *
     * Null when the title is empty. The author is sent only to Open Library, which is the
     * only one of the three whose search takes one.
     */
    fun request(provider: CoverTitleProvider, title: String, author: String? = null): CoverFetch? {
        val trimmed = title.trim()
        if (trimmed.isEmpty()) return null
        return when (provider) {
            CoverTitleProvider.OPEN_LIBRARY -> CoverFetch(url = openLibraryUrl(trimmed, author))
            CoverTitleProvider.ANILIST -> CoverFetch(
                url = "https://graphql.anilist.co",
                method = "POST",
                body = buildJsonObject {
                    put("query", ANILIST_QUERY)
                    put("variables", buildJsonObject { put("search", trimmed) })
                }.toString(),
            )
            CoverTitleProvider.MANGA_UPDATES -> CoverFetch(
                url = "https://api.mangaupdates.com/v1/series/search",
                method = "POST",
                body = buildJsonObject {
                    put("search", trimmed)
                    put("perpage", 10)
                }.toString(),
            )
        }
    }

    private fun openLibraryUrl(title: String, author: String?): String {
        fun encoded(value: String) = URLEncoder.encode(value, Charsets.UTF_8.name())
        val terms = buildList {
            add("title=${encoded(title)}")
            author?.trim()?.takeIf { it.isNotEmpty() }?.let { add("author=${encoded(it)}") }
            add("limit=10")
            // Only the three fields a candidate draws. Open Library's default document is
            // large and most of it describes editions nobody here is choosing between.
            add("fields=${encoded("title,author_name,cover_i")}")
        }
        return "https://openlibrary.org/search.json?" + terms.joinToString("&")
    }

    /**
     * The candidates in one provider's answer, or none.
     *
     * A malformed answer reads as no candidates rather than as an error: `cover-art` says a
     * provider that does not answer leaves the publication with the cover it had, and a
     * provider that answers nonsense has not answered.
     */
    /** What a title search is cached under: the words asked, not the publication asking. */
    fun cacheKey(title: String, author: String?, providers: List<CoverTitleProvider>): String =
        listOf(
            title.trim().lowercase(),
            author?.trim()?.lowercase().orEmpty(),
            providers.joinToString(",") { it.name },
        ).joinToString("|")

    fun candidates(body: ByteArray, provider: CoverTitleProvider): List<CoverCandidate> =
        runCatching {
            val root = json.parseToJsonElement(String(body)).jsonObject
            when (provider) {
                CoverTitleProvider.OPEN_LIBRARY -> openLibraryCandidates(root)
                CoverTitleProvider.ANILIST -> aniListCandidates(root)
                CoverTitleProvider.MANGA_UPDATES -> mangaUpdatesCandidates(root)
            }
        }.getOrElse { emptyList() }

    private fun openLibraryCandidates(root: JsonObject): List<CoverCandidate> =
        root["docs"]?.jsonArray.orEmpty().mapNotNull { element ->
            val document = element.jsonObject
            // A document with no `cover_i` has no picture, so it is not a candidate however
            // well its title matches.
            // `intOrNull` and `contentOrNull` throughout: Kotlin's `int` throws on a JSON null
            // and empties the whole list, and `content` reads a JSON null as the word "null".
            val identifier = document["cover_i"]?.jsonPrimitive?.intOrNull ?: return@mapNotNull null
            CoverCandidate(
                title = document["title"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                imageUrl = "https://covers.openlibrary.org/b/id/$identifier-L.jpg",
                provider = CoverTitleProvider.OPEN_LIBRARY,
                subtitle = document["author_name"]?.jsonArray?.firstOrNull()
                    ?.jsonPrimitive?.contentOrNull,
            )
        }

    private fun aniListCandidates(root: JsonObject): List<CoverCandidate> =
        root["data"]?.jsonObject?.get("Page")?.jsonObject?.get("media")?.jsonArray.orEmpty()
            .mapNotNull { element ->
                val entry = element.jsonObject
                val titles = entry["title"]?.jsonObject
                val name = titles?.get("english")?.jsonPrimitive?.contentOrNull
                    ?: titles?.get("romaji")?.jsonPrimitive?.contentOrNull.orEmpty()
                val address = entry["coverImage"]?.jsonObject?.get("large")
                    ?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
                CoverCandidate(name, address, CoverTitleProvider.ANILIST)
            }

    private fun mangaUpdatesCandidates(root: JsonObject): List<CoverCandidate> =
        root["results"]?.jsonArray.orEmpty().mapNotNull { element ->
            val record = element.jsonObject["record"]?.jsonObject ?: return@mapNotNull null
            val address = record["image"]?.jsonObject?.get("url")?.jsonObject?.get("original")
                ?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            CoverCandidate(
                title = record["title"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                imageUrl = address,
                provider = CoverTitleProvider.MANGA_UPDATES,
            )
        }
}

/**
 * Candidates for a title, from every provider that answers, for the reader to choose from.
 *
 * Not cached, and that is the difference between this and [CoverLookupClient.cover]. An
 * exact lookup has one answer worth remembering; a title search is a reader looking, and a
 * reader who looks twice has changed what they are looking for.
 */
suspend fun CoverLookupClient.candidates(
    title: String,
    author: String? = null,
    providers: List<CoverTitleProvider> = CoverTitleProvider.entries,
): List<CoverCandidate> {
    if (!isEnabled()) return emptyList()
    // Cached like an identifier lookup: `cover-art` asks that the same publication is never
    // looked up twice, and a title search is a lookup.
    val key = CoverTitleSearch.cacheKey(title, author, providers)
    cache.candidates(key)?.let { return it }
    val found = providers.flatMap { provider ->
        val request = CoverTitleSearch.request(provider, title, author)
            ?: return@flatMap emptyList()
        val answered = transport.send(request) ?: return@flatMap emptyList()
        if (answered.status !in 200..299) {
            emptyList()
        } else {
            CoverTitleSearch.candidates(answered.body, provider)
        }
    }
        // A picture is only ever fetched from a listed host, so a candidate elsewhere is one
        // the reader could choose and never see. And one picture is one candidate: two rows
        // for one address are one choice, and a list keyed on the address cannot hold both.
        .filter { CoverImageHosts.allows(it.imageUrl) }
        .distinctBy { it.imageUrl }
    cache.recordCandidates(key, found)
    return found
}
