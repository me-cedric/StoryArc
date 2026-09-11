package app.storyarc.core.model

import java.util.UUID
import kotlinx.serialization.Serializable

/**
 * The two numbers Kavita writes when it means "this has no number", as it writes them into
 * a name.
 *
 * Quoted from `Kavita.Models/Constants/ParserConstants.cs`:
 * `public const string LooseLeafVolume = "-100000";` and
 * `public const string SpecialVolume = "100000";`
 *
 * Kavita derives a chapter's title and a volume's name from the number, so both sentinels
 * reach this app as text as well as as integers. Here, in the module underneath, because a
 * card read from disk needs the same answer as a chapter read from the wire -- and the
 * whole defect was four places asking the question separately and disagreeing.
 */
val SENTINEL_NAMES: Set<String> = setOf("-100000", "100000")

/**
 * One thing a search of a Kavita server matched.
 *
 * `kavita-server` asks a server-side search for "matches across series, chapters, people,
 * genres, and tags -- not only titles cached locally". A genre and a tag are the same kind of
 * thing to a reader, so they arrive as one kind here, for the reason [KavitaCard.subjects]
 * gives.
 */
data class KavitaHit(
    val kind: Kind,
    val title: String,
    /**
     * The series this leads to, or zero when it leads nowhere.
     *
     * A person and a subject are names the server matched, not places: Kavita answers with
     * the name alone, and a row that looked tappable and did nothing would be worse than a
     * row that plainly is not.
     */
    val seriesId: Int = 0,
    /**
     * The download on this device this row opens, when the row came from the cache.
     *
     * Null for everything the server answered: the server knows about publications this
     * device has never held. Set for a cached row, which is the difference that matters --
     * with the server away, a row that cannot be opened is a row that is only there to
     * disappoint.
     *
     * The *download's* identifier, not the publication's. They are two different keys and
     * driving this proved it: a download is filed under what the server calls the chapter, and
     * the publication under the path the file ended up at.
     */
    val downloadId: String? = null,
    /**
     * Which chapter this row is, when the row is a chapter.
     *
     * Part of [id] and nothing else. Two chapters of one series can carry the same words --
     * both untitled, both unnumbered -- and without this they were one key, which a keyed
     * list refuses: the search screen crashed on a server that held two such chapters.
     */
    val chapterId: Int = 0,
) {
    /** Which of the spec's five a match is, and therefore which heading it appears under. */
    enum class Kind {
        SERIES,
        CHAPTER,
        PERSON,

        /** A genre or a tag. Kavita keeps them apart; a reader looking for "horror" does not. */
        SUBJECT,
    }

    /**
     * Identity is what the row *is*, not where it came from: the same series found twice --
     * once by its own name, once through a chapter -- is one row, and a list keyed on
     * anything finer would draw it twice.
     */
    val id: String get() = "$kind:$seriesId:$chapterId:$title"

    /** Whether opening this row leads anywhere. */
    val isOpenable: Boolean get() = seriesId > 0
}

/**
 * What a server said about a publication, kept so it can be read without the server.
 *
 * `kavita-server`: "when a downloaded Kavita publication is opened with the server
 * unreachable, the cached server metadata is displayed, not the file's embedded metadata".
 * The file has its own `ComicInfo.xml` and the spec is explicit that the server wins, so what
 * the server said has to survive the server going away -- which means being written down when
 * the download is taken, not fetched when the reader arrives.
 *
 * A value with no network and no disk in it. `KavitaCardStore` writes it; iOS's `KavitaCard`
 * mirrors it field for field.
 */
@Serializable
data class KavitaCard(
    /**
     * The publication this describes, which is the identity the library computes for the
     * downloaded file and therefore what the shelf looks the card up by.
     */
    val publicationId: String,
    /**
     * The download the file belongs to, which is a different key.
     *
     * `Download.id` is what the *source* calls the thing -- for Kavita, the server's chapter.
     * The publication's identity is the path the bytes ended up at. Both are needed and
     * neither can be derived from the other, so the card holds both.
     */
    val downloadId: String = "",
    /** Which source it came from, so removing a server can take its cards with it. */
    val sourceId: String,
    /**
     * The whole chain Kavita keys its own rows by, not the chapter alone.
     *
     * `KavitaOrigin` carries the same four for the same reason: a progress post missing one
     * of them is refused, and a card that could not rebuild the origin would be a download
     * that reads offline and never reports what was read.
     */
    val libraryId: Int = 0,
    val seriesId: Int,
    val chapterId: Int,
    /**
     * The names, defaulted for the bytes and not for the caller.
     *
     * `KavitaCardStore` decodes every card as one map with a single `runCatching`, so one row
     * kotlinx.serialization refuses does not lose two fields -- it loses the reader's whole
     * offline library. A `MissingFieldException` for a name is not worth that, which is the
     * same reasoning that gave iOS's `KavitaCard` a hand-written decoder.
     */
    val seriesName: String = "",
    val chapterName: String = "",
    val summary: String? = null,
    val people: List<String> = emptyList(),
    /** Genres and tags read as one list; the distinction is Kavita's, not the reader's. */
    val subjects: List<String> = emptyList(),
    val releaseYear: Int = 0,
    /**
     * Kavita's own `ageRating` number, so the rating outlives the server.
     *
     * The number rather than a name, because `:core:model` is where a card lives and the
     * table that reads it is Kavita's: `KavitaAgeRating` in `:core:kavita` turns this into a
     * label, and `KavitaCard.rating` applies the same two rules the live answer gets.
     *
     * Zero is Kavita's own `Unknown`, which is not a rating and draws no line -- so it is
     * both the right default for a card written before this field existed and the right
     * value for a keep whose server had no metadata to give.
     */
    val ageRating: Int = 0,
    /**
     * Kavita's own `publicationStatus` number, or -1 for a card that never recorded one.
     *
     * **The sentinel is the point.** Kavita's own range is 0 to 4 and *zero means OnGoing* --
     * a real state a curator chose, not an absence. A card written before this field existed
     * would decode zero and the screen would state that the series is running, which the
     * server may never have said. -1 is outside Kavita's table, so `KavitaPublicationStatus`
     * reads it as a number it has never heard of and the line is left unsaid.
     */
    val publicationStatus: Int = -1,
) {
    /**
     * Everything a one-line summary row shows, already in order.
     *
     * The same line `KavitaMetadata`'s facts build from a live answer, so a series read
     * offline reads the way it did online rather than losing its shape with its server.
     */
    val facts: List<String>
        get() = (if (releaseYear > 0) listOf(releaseYear.toString()) else emptyList()) +
            people + subjects

    /**
     * This publication as the server describes it, rather than as its file does.
     *
     * **Both of `kavita-server`'s metadata scenarios are this one function.** "When a
     * publication's `ComicInfo.xml` disagrees with Kavita's metadata, the app displays
     * Kavita's values, because the server is the curated source"; and "when a downloaded
     * Kavita publication is opened with the server unreachable, the cached server metadata is
     * displayed, not the file's embedded metadata". The second is the first, applied from disk
     * instead of from a live answer -- which is the whole reason the card is written down when
     * the download is taken.
     *
     * The result is [MetadataOrigin.AUTHORITATIVE], so nothing downstream silently puts the
     * file's values back: that ordering already exists and this is what it was for.
     *
     * A field the card is silent about keeps what the file said. The server not having a
     * summary is not the server saying there is none, and blanking a description the file does
     * have would be losing information in the name of preferring a source.
     *
     * [ageRating] and [publicationStatus] do not pass through here, and cannot: [Publication]
     * has no slot for either, and no local file states them. They stay on the card and the
     * screen reads them from it -- the same shape the live path uses, where they are named
     * lines rather than members of the run of facts.
     */
    /**
     * The row this download is a copy of, as the library's own identifier for it.
     *
     * `library-browsing`: a publication a source offers and the same publication downloaded
     * are one row. They were two, and the reason was spelling: a server row is identified by
     * `ServerIdentifier(sourceId, "chapter:<id>")`, and a downloaded file is identified by
     * its path and its digest -- so `PublicationIdentity.matches` had nothing in common to
     * match on and the library drew the download beside the row it came from.
     *
     * The card is what bridges them, because it is written at the moment the chapter is kept
     * and holds both the source and the chapter. The spelling here has to be the one
     * `KavitaContributor` uses, and `KavitaDownloadIsOneRowTest` is what holds the two
     * together.
     *
     * Null when the card's source is not a UUID, which is a card written by something that
     * was not this app.
     */
    /**
     * The chapter's name, or null where what was written down was a sentinel.
     *
     * **Read-time rather than a migration.** A card is written once, at the moment a
     * chapter is kept, and nothing rewrites it. Cards kept before the guard existed hold
     * "-100000" as the chapter's name, and that string wins over the file's own title
     * because a card is `AUTHORITATIVE`. Checking here repairs every such card the first
     * time it is read, on a device nobody can reach to migrate.
     */
    val properChapterName: String?
        get() = chapterName.takeIf { it.isNotBlank() && it !in SENTINEL_NAMES }

    val remoteIdentity: PublicationIdentity.ServerIdentifier?
        get() = runCatching { UUID.fromString(sourceId) }.getOrNull()?.let { source ->
            PublicationIdentity.ServerIdentifier(sourceId = source, remoteId = "chapter:$chapterId")
        }

    fun appliedTo(publication: Publication): Publication = publication.copy(
        displayTitle = properChapterName ?: publication.displayTitle,
        series = seriesName.ifEmpty { null } ?: publication.series,
        authors = people.ifEmpty { publication.authors },
        year = if (releaseYear > 0) releaseYear else publication.year,
        summary = summary?.takeIf { it.isNotEmpty() } ?: publication.summary,
        tags = subjects.ifEmpty { publication.tags },
        origin = MetadataOrigin.AUTHORITATIVE,
    )
}

/**
 * Searching a Kavita source, and what a search falls back to when the server is away.
 *
 * Pure, and deliberately so: `kavita-server` has two search scenarios and the difference
 * between them is a decision, not a screen. iOS's `KavitaFind` mirrors it, asserted against
 * the same table in the same order.
 */
object KavitaFind {
    /**
     * The term a query actually asks for, or null when it asks for nothing.
     *
     * Whitespace alone is nothing. A server asked for it answers with its whole library,
     * which reads as a search that matched everything.
     */
    fun term(raw: String): String? = raw.trim().ifEmpty { null }

    /**
     * What a term matches in what this device already holds.
     *
     * `kavita-server`: with the server unreachable "the search falls back to the local cache
     * and states that results are limited to cached content". The cache is the cards kept
     * beside downloads -- the only Kavita metadata that is ever written to disk, for the
     * reason `sources` gives for not writing the rest of a server's answers down.
     *
     * The order is the spec's own -- series, chapters, people, genres and tags -- rather than
     * a ranking. A reader who cannot reach their server is looking for a particular book they
     * already have, and the shape of the answer should not change with the server's mood.
     */
    fun inCache(term: String, cards: List<KavitaCard>): List<KavitaHit> {
        val needle = term(term)?.lowercase() ?: return emptyList()
        val hits = mutableListOf<KavitaHit>()
        val seen = mutableSetOf<String>()

        fun add(hit: KavitaHit) {
            if (seen.add(hit.id)) hits += hit
        }

        fun matches(text: String) = text.lowercase().contains(needle)

        // A series row opens the first chapter of it this device holds. Offline there is
        // nothing else it could open -- the series itself lives on a server that is not
        // answering, and the reader asked for something they can read now.
        cards.filter { matches(it.seriesName) }.forEach {
            add(KavitaHit(KavitaHit.Kind.SERIES, it.seriesName, it.seriesId, it.downloadId))
        }
        cards.filter { matches(it.chapterName) }.forEach {
            add(
                KavitaHit(
                    KavitaHit.Kind.CHAPTER,
                    it.properChapterName.orEmpty(),
                    it.seriesId,
                    it.downloadId,
                    chapterId = it.chapterId,
                ),
            )
        }
        cards.forEach { card ->
            card.people.filter(::matches).forEach { add(KavitaHit(KavitaHit.Kind.PERSON, it)) }
        }
        cards.forEach { card ->
            card.subjects.filter(::matches).forEach { add(KavitaHit(KavitaHit.Kind.SUBJECT, it)) }
        }
        return hits
    }

    /**
     * One search's hits under their headings, in the spec's own order.
     *
     * A kind that matched nothing is left out rather than drawn as a heading over nothing,
     * which is the rule `library-browsing` applies to its own group headings.
     */
    fun grouped(hits: List<KavitaHit>): List<Pair<KavitaHit.Kind, List<KavitaHit>>> =
        KavitaHit.Kind.entries.mapNotNull { kind ->
            hits.filter { it.kind == kind }.takeIf { it.isNotEmpty() }?.let { kind to it }
        }
}
