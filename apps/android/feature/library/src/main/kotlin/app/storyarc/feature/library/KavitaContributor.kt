package app.storyarc.feature.library

import app.storyarc.core.kavita.KavitaChapter
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.kavita.KavitaSeries
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
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
     * One request for the page, then one per series for its chapters -- so this number is
     * the request count, near enough. Sixty fills several screens of a grid and finishes in
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
    )

    suspend fun page(sourceId: UUID, client: KavitaClient, page: Int): Page {
        val series = client.recentSeries(page = page, size = FIRST_SLICE)
        val chapters = mutableListOf<KavitaChapter>()
        val publications = series.flatMap { each ->
            val read = retriedOnce { chapters(client, each) }
            chapters += read
            read.map { chapter -> publication(sourceId, each, chapter) }
        }
        // A full page is the only evidence a server has more, and it is evidence rather
        // than proof: a library of exactly sixty series reads as partial once, and says so
        // until the page comes back short. Overstating what is held back is the safe way
        // round -- the other way tells a reader their five-thousand-title server has 137.
        return Page(
            slice = SourceSlice(publications, holdsMore = series.size >= FIRST_SLICE),
            seriesRead = series.size,
            chapters = chapters,
        )
    }

    private suspend fun chapters(client: KavitaClient, series: KavitaSeries): List<KavitaChapter> =
        client.volumes(series.id).flatMap { it.chapters }

    /**
     * [fetch], retried once on failure before it is treated as empty.
     *
     * A free function so a test can prove the retry without a server: `KavitaContributorTest`
     * counts calls through a fake [fetch] that fails once, and mutating this back to a single
     * attempt makes that test fail by name.
     */
    internal suspend fun <T> retriedOnce(fetch: suspend () -> List<T>): List<T> =
        runCatching { fetch() }.recoverCatching { fetch() }.getOrDefault(emptyList())

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
