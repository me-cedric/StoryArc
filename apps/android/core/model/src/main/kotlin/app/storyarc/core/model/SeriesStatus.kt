package app.storyarc.core.model

/**
 * The library with a reader-set status filled in for every series whose source reports
 * none.
 *
 * `library-browsing` (D36): a status a source reports is never the reader's to change, so
 * this only ever fills a `null` [Publication.status] and never replaces one a source already
 * set. A free function rather than a method on the override store itself, so
 * `LibraryViewModel` can apply it wherever it reads the raw library -- the shelf it arranges
 * and the values the filter menu offers -- through the one call, instead of threading the
 * override into every place a scan or a Kavita answer appends to the library. iOS's
 * `withManualStatuses(_:overrides:)` mirrors it.
 */
fun withManualStatuses(
    publications: List<Publication>,
    overrides: Map<String, PublicationStatus>,
): List<Publication> = publications.map { publication ->
    val series = publication.series
    if (publication.status != null || series == null) {
        publication
    } else {
        val override = overrides[series]
        if (override == null) publication else publication.copy(status = override)
    }
}
