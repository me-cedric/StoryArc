package app.storyarc.core.catalogue

import app.storyarc.core.model.PublicationFormat

/**
 * Which acquisition to take, which the reader could choose instead, and which the app has to
 * refuse.
 *
 * Beside the feed rather than beside the download queue: the question is about a *catalogue
 * entry*, and the answer is asked long before anything is downloaded -- the grid asks it to
 * decide whether a cell is tappable, and the detail screen asks it to lay out the formats as
 * a choice. iOS's `CatalogueAcquisition` is the same four answers.
 */
object CatalogueAcquisition {
    /**
     * `opds-catalog`: "the app selects EPUB for reflowable reading and lets the user choose
     * another format". EPUB first, then the comic containers, then PDF -- a comic offered as
     * both CBZ and PDF is a comic, and the PDF is a worse copy of it.
     */
    fun best(entry: OpdsEntry): OpdsAcquisition? = readable(entry).firstOrNull()

    /**
     * Every acquisition this app could act on, best first.
     *
     * Ordered by what the app would pick rather than by what the feed listed, because this is
     * what the detail screen shows as the choice: the default belongs at the top of it, and a
     * reader scanning down the list is scanning down a ranking. `sortedBy` is stable, so two
     * of one format keep the order the feed listed them in.
     */
    fun readable(entry: OpdsEntry): List<OpdsAcquisition> = entry.acquisitions
        .filter { it.kind.isFetchable && PublicationFormat.ofMediaType(it.mediaType)?.isOpenable == true }
        .sortedBy(::rank)

    /**
     * The formats offered as a plain download that this app cannot open.
     *
     * `opds-catalog`: an entry with nothing readable is "listed but marked unreadable, naming
     * the formats offered". These are the names -- a media type verbatim when it maps to no
     * format at all, and CB7 when it maps to one the decoder does not exist for.
     */
    fun unreadable(entry: OpdsEntry): List<String> = entry.acquisitions
        .filter { it.kind.isFetchable }
        .filter { PublicationFormat.ofMediaType(it.mediaType)?.isOpenable != true }
        .map { PublicationFormat.ofMediaType(it.mediaType)?.displayName ?: it.mediaType }
        .filter { it.isNotEmpty() }
        // Deduplicated and ordered: a server that offers the same type twice offers one
        // format, and a list that says "PDF, PDF" reads as a bug in the app.
        .distinct()
        .sorted()

    /**
     * The ways of obtaining this the app will not follow, each named once.
     *
     * `opds-catalog`: an indirect acquisition -- "an OPDS-LCP or borrow flow" -- makes the app
     * "state that the acquisition type is not supported rather than failing silently". A
     * screen can only state it if something hands it the list, so this is that list.
     */
    fun unsupported(entry: OpdsEntry): List<OpdsAcquisition.Kind> = entry.acquisitions
        .filterNot { it.kind.isFetchable }
        .map { it.kind }
        .distinct()

    private fun rank(acquisition: OpdsAcquisition): Int =
        when (PublicationFormat.ofMediaType(acquisition.mediaType)) {
            PublicationFormat.EPUB -> 0
            PublicationFormat.CBZ, PublicationFormat.CBT, PublicationFormat.CBR -> 1
            PublicationFormat.PDF -> 2
            else -> 3
        }
}
