package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.kavita.KavitaVolume
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.PublicationStatus
import app.storyarc.core.persistence.KavitaOrigin
import app.storyarc.core.persistence.KavitaProgressStore
import java.util.UUID

/**
 * What a Kavita server puts in the library.
 *
 * `library-browsing` requires one library over every source: "publications from every
 * configured source are shown together", and "nothing on the shelf states which source a
 * publication came from". Until this, only a folder scan reached the grid, so a reader with
 * a server saw the files on their device and nothing else.
 *
 * **A chapter is the publication, not a series.** A row in the library is something a reader
 * opens, and a series opens a list -- which is what the browser already is. A chapter is
 * also what everything downstream already keys on: `KavitaProgressStore` records a position
 * against one, the download path fetches one, and `PublicationIdentity.serverIdentifier`
 * wants a remote id that names something fetchable.
 *
 * **The first read is a slice, newest first.** A server with forty thousand series is
 * minutes of requests and a cache nobody asked for. `Series/recently-added-v2` pages, and
 * what arrived last is what a reader recognises when they open the app. What is not in the
 * slice stays reachable through search and through the server's own browser, which is what
 * `library-browsing`'s *More from a source than the library holds* already requires.
 */
internal object KavitaContributor {

    /**
     * How many series the first read of a server takes.
     *
     * One request for the page, then two per series, for its chapters and its status -- so
     * this number is half the request count, near enough. Sixty fills several screens of a grid and finishes in
     * a few seconds on a server on the far side of a home connection. It is a starting
     * value chosen to be re-chosen: `design.md` leaves it open, and the number wants a
     * reader's judgement about how much of a library should arrive before they can scroll.
     */
    const val FIRST_SLICE = 60

    /**
     * One page of a server's most recently added series, as publications, and how many
     * series that page held.
     *
     * `sources`' *More from a source than the library holds*: the first read is
     * [publications], page one, and `LibraryViewModel.continueReadingServers` asks for
     * every page after it the same way, so there is one function that knows how a Kavita
     * page becomes a slice rather than the first read and the continuation each carrying
     * their own copy of it.
     *
     * A series whose chapters cannot be read is skipped rather than failing the round: one
     * unreadable series must not cost a reader the rest of the page.
     *
     * **One retry, immediately, before it is skipped.** The page still counts the series as
     * read either way -- the server's own page cursor moved past it, and asking for the
     * same page again is not this page's job. Without the retry, a request that fails once
     * for a reason that clears itself (a socket hiccup, a server briefly busy) drops that
     * series until it happens to fall inside a future page's own slice again, which a large,
     * steadily growing server may never do.
     */
    data class Page(
        val slice: SourceSlice,
        /**
         * Series read in this page, which is what the source detail screen counts --
         * distinct from `slice.publications.size`, a chapter total that means nothing to a
         * reader who thinks of a library in series.
         */
        val seriesRead: Int,
        /**
         * The chapters this page read, each still carrying the server's own `pagesRead`.
         *
         * What [KavitaSync.pull] needs, and what building [slice] already asked every one
         * of these series for -- the library's own refresh of a source is a pull's other
         * caller, and it has no reason to ask the server the same question twice.
         */
        val chapters: List<KavitaChapter>,
        /**
         * Series on this page whose volumes call failed twice and was skipped, so nothing
         * of theirs is in [slice] or [chapters].
         *
         * A continuation page is asked for once: nothing here re-asks for this page later,
         * so a series that fails here would otherwise be lost until the whole first-slice-
         * and-continuation read starts over. [retry] is the second chance -- a caller keeps
         * this list (`KavitaFailedSeriesStore` does) and feeds it back in on a later read.
         */
        val failedSeriesIds: List<Int> = emptyList(),
    )

    /**
     * @param store Where every chapter this read sees is catalogued, so a reading list or a
     *   mark can reach Kavita for a row the reader has only ever seen on a shelf, never
     *   opened or kept. Null skips the catalogue, for a caller with no progress store at all.
     */
    suspend fun page(
        sourceId: UUID,
        client: KavitaClient,
        page: Int,
        store: KavitaProgressStore? = null,
    ): Page {
        val series = client.recentSeries(page = page, size = FIRST_SLICE)
        val chapters = mutableListOf<KavitaChapter>()
        val origins = mutableMapOf<String, KavitaOrigin>()
        val failed = mutableListOf<Int>()
        val publications = series.flatMap { each ->
            val volumes = retriedOnceOrNull { client.volumes(each.id) }
            if (volumes == null) {
                failed += each.id
                return@flatMap emptyList()
            }
            val status = if (volumes.isEmpty()) null else seriesStatus(client, each.id)
            volumes.flatMap { volume ->
                chapters += volume.chapters
                origins += catalogOrigins(sourceId, each, volume)
                volume.chapters.map { chapter -> publication(sourceId, each, chapter, status) }
            }
        }
        store?.rememberCatalog(origins)
        // A full page is the only evidence a server has more, and it is evidence rather
        // than proof: a library of exactly sixty series reads as partial once, and says so
        // until the page comes back short. Overstating what is held back is the safe way
        // round -- the other way tells a reader their five-thousand-title server has 137.
        return Page(
            slice = SourceSlice(publications, holdsMore = series.size >= FIRST_SLICE),
            seriesRead = series.size,
            chapters = chapters,
            failedSeriesIds = failed,
        )
    }

    /** What one retry pass over [KavitaFailedSeriesStore]'s pending series produced. */
    data class RetryResult(
        /** What a series that now answers put in the library. */
        val publications: List<Publication>,
        /** Series that still failed, and so are still pending for the next pass. */
        val stillFailed: List<Int>,
    )

    /**
     * Gives every series in [seriesIds] one more try, instead of leaving it lost until the
     * whole first-slice-and-continuation read starts over.
     *
     * Asked for by id rather than walked by page: [seriesIds] came from pages this source
     * already read past, so re-reading the page they were on would also re-read everything
     * around them that already succeeded. `Series/{id}` is the one request this needs per
     * series, the same route a reader's own tap on a search result already uses.
     */
    suspend fun retry(
        sourceId: UUID,
        client: KavitaClient,
        seriesIds: Set<Int>,
        store: KavitaProgressStore? = null,
    ): RetryResult {
        val publications = mutableListOf<Publication>()
        val origins = mutableMapOf<String, KavitaOrigin>()
        val stillFailed = mutableListOf<Int>()
        for (id in seriesIds) {
            val series = runCatching { client.seriesDetail(id) }.getOrNull()
            val volumes = series?.let { retriedOnceOrNull { client.volumes(it.id) } }
            if (series == null || volumes == null) {
                stillFailed += id
                continue
            }
            val status = if (volumes.isEmpty()) null else seriesStatus(client, series.id)
            volumes.forEach { volume ->
                origins += catalogOrigins(sourceId, series, volume)
                volume.chapters.forEach { chapter ->
                    publications += publication(sourceId, series, chapter, status)
                }
            }
        }
        store?.rememberCatalog(origins)
        return RetryResult(publications, stillFailed)
    }

    /**
     * Where each of a volume's chapters sits on the server, keyed by the row it becomes.
     *
     * Lifted beside [publication] so `KavitaContributorCatalogOriginTest` can prove it
     * without a server -- the twin of iOS's `KavitaContributor.catalogOrigins`.
     */
    internal fun catalogOrigins(
        sourceId: UUID,
        series: KavitaSeries,
        volume: KavitaVolume,
    ): Map<String, KavitaOrigin> = volume.chapters.associate { chapter ->
        publication(sourceId, series, chapter).id to KavitaOrigin(
            sourceId = sourceId.toString(),
            libraryId = series.libraryId,
            seriesId = series.id,
            volumeId = volume.id,
            chapterId = chapter.id,
            pages = chapter.pages,
        )
    }

    /**
     * [fetch], retried once on failure before it is treated as empty.
     *
     * A free function so a test can prove the retry without a server: `KavitaContributorTest`
     * counts calls through a fake [fetch] that fails once, and mutating this back to a single
     * attempt makes that test fail by name.
     */
    internal suspend fun <T> retriedOnce(fetch: suspend () -> List<T>): List<T> =
        retriedOnceOrNull(fetch) ?: emptyList()

    /**
     * [fetch], retried once on failure, or null when both attempts failed.
     *
     * [retriedOnce]'s own default -- empty on failure -- is exactly what loses a series that
     * still fails after this: empty reads the same as a series that genuinely has no
     * volumes, so nothing downstream could tell "skip this one, it never comes back on its
     * own" from "this one has nothing to show". [page] uses this instead, so a failure stays
     * a failure all the way to [RetryResult] and [retry] gets another chance at it.
     */
    internal suspend fun <T> retriedOnceOrNull(fetch: suspend () -> List<T>): List<T>? =
        runCatching { fetch() }.recoverCatching { fetch() }.getOrNull()

    /**
     * The status the server reports for one series, or null when it could not be read.
     *
     * `library-browsing` (D36): the status a source reports is carried onto the row, so the
     * filter covers a server's series and not only the ones a reader downloaded. One more
     * request per series that has chapters. A failure costs the row its status, never the
     * row: the series screen then treats it as a series with no reported status.
     */
    private suspend fun seriesStatus(client: KavitaClient, seriesId: Int): PublicationStatus? =
        runCatching { client.metadata(seriesId).publicationStatus }
            .getOrNull()
            .let(PublicationStatus::ofKavita)

    /**
     * One chapter as a row in the library.
     *
     * No `normalizedPath`, which is the whole of what makes it a remote row: nothing is on
     * disk, so the library's cover resolver and its availability axis both read it as
     * needing its source. When the same chapter is downloaded, the identity's server half
     * matches and the two become one row -- `PublicationIdentity.matches` prefers the
     * server's own answer, which is ADR-0006's order and is why no new rule is needed here.
     */
    internal fun publication(
        sourceId: UUID,
        series: KavitaSeries,
        chapter: KavitaChapter,
        status: PublicationStatus? = null,
    ): Publication = Publication(
        identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(
                sourceId = sourceId,
                remoteId = "chapter:${chapter.id}",
            ),
        ),
        // What the server says the series is, which is as much as anything knows before the
        // file is fetched. A reader who downloads it gets the container's own answer, and
        // the row is re-indexed from the file at that point.
        format = format(series.format),
        displayTitle = KavitaNaming.title(series, chapter),
        series = series.name,
        number = KavitaNaming.issueNumber(chapter),
        pageCount = chapter.pages.takeIf { it > 0 },
        status = status,
        // The server owns these answers, which is what `AUTHORITATIVE` means and why a
        // downloaded copy's embedded metadata does not overwrite them.
        origin = MetadataOrigin.AUTHORITATIVE,
        sourceId = sourceId,
    )

    /**
     * Kavita's `MangaFormat` as this app's own.
     *
     * A guess with one visible consequence, stated rather than hidden: Kavita says
     * "archive", not which archive, so every comic on a server files as `CBZ` until it is
     * downloaded and read. The format filter therefore lists a CBR on a server under CBZ.
     * The alternative is a format the filter cannot show at all, which is worse: a reader
     * filtering for comics would lose the server's whole catalogue.
     */
    private fun format(kavita: Int): PublicationFormat = when (kavita) {
        FORMAT_IMAGE -> PublicationFormat.IMAGE_FOLDER
        FORMAT_EPUB -> PublicationFormat.EPUB
        FORMAT_PDF -> PublicationFormat.PDF
        else -> PublicationFormat.CBZ
    }

    private const val FORMAT_IMAGE = 0
    private const val FORMAT_EPUB = 3
    private const val FORMAT_PDF = 4
}
