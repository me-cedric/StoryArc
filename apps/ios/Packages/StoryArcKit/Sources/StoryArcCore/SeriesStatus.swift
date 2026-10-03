/// The library with a reader-set status filled in for every series whose source reports
/// none.
///
/// `library-browsing` (D36): a status a source reports is never the reader's to change, so
/// this only ever fills a `nil` ``Publication/status`` and never replaces one a source
/// already set. A free function rather than a method on the override store itself, so
/// `LibraryModel` can apply it wherever it reads the raw library — the shelf it arranges and
/// the values the filter menu offers — through the one call, instead of threading the
/// override into every place a scan or a Kavita answer appends to the library. Android's
/// `withManualStatuses` mirrors it.
public func withManualStatuses(
    _ publications: [Publication],
    overrides: [String: PublicationStatus]
) -> [Publication] {
    publications.map { publication in
        guard publication.status == nil, let series = publication.series,
              let override = overrides[series]
        else { return publication }
        var next = publication
        next.status = override
        return next
    }
}
