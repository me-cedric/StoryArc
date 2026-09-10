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
     * The chapters of a server's most recently added series, as publications.
     *
     * A series whose chapters cannot be read is skipped rather than failing the round: one
     * unreadable series must not cost a reader the other fifty-nine.
     */
    suspend fun publications(sourceId: UUID, client: KavitaClient): List<Publication> {
        val series = client.recentSeries(page = 1, size = FIRST_SLICE)
        return series.flatMap { each ->
            val chapters = runCatching { chapters(client, each) }.getOrDefault(emptyList())
            chapters.map { chapter -> publication(sourceId, each, chapter) }
        }
    }

    private suspend fun chapters(client: KavitaClient, series: KavitaSeries): List<KavitaChapter> =
        client.volumes(series.id).flatMap { it.chapters }

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
        displayTitle = title(series, chapter),
        series = series.name,
        number = chapter.number.takeIf { it.isNotEmpty() },
        pageCount = chapter.pages.takeIf { it > 0 },
        // The server owns these answers, which is what `AUTHORITATIVE` means and why a
        // downloaded copy's embedded metadata does not overwrite them.
        origin = MetadataOrigin.AUTHORITATIVE,
        sourceId = sourceId,
    )

    /**
     * What to call one chapter.
     *
     * Three cases, and the first two were wrong before this. A chapter with a title of its
     * own keeps it. A numbered one reads `<series> #<number>`, the house format, because a
     * cell headed "43" names nothing. And Kavita writes `-100000` for a chapter that has no
     * number at all -- a collected edition, a volume with one part -- which is not a number
     * and leaves the series' own name, which is what the reader would have called it.
     */
    private fun title(series: KavitaSeries, chapter: KavitaChapter): String {
        chapter.title?.takeIf { it.isNotBlank() }?.let { return it }
        val numbered = chapter.number.takeIf { it.isNotBlank() && !it.startsWith("-") }
        // `<series> #<number>`, which is the house format `seriesLine` composes and what a
        // filename-derived title already looks like -- so a server's issue and a scanned
        // one read the same, and the caption below suppresses itself as it does for a file.
        // The bare number was the bug: a shelf of cells headed "43" says nothing, and the
        // caption under it then carried the only words on the cell.
        return numbered?.let { "${series.name} #$it" } ?: series.name
    }

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
