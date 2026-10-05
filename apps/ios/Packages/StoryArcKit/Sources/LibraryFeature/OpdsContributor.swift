import Catalogue
import Foundation
import StoryArcCore

/// What an OPDS catalogue puts in the library.
///
/// `library-browsing` requires one library over every source. A catalogue was reachable
/// only by browsing to it, which made it a place a reader travels to rather than part of
/// their library.
///
/// **One feed, not a crawl.** A catalogue is a tree of feeds and this reads the one the
/// reader saved. What is deeper stays reachable through the browser and through search,
/// which is what *More from a source than the library holds* already requires.
///
/// **No acquisition URL is kept.** An OPDS acquisition link can carry a key in its query,
/// and `sources` forbids a cached catalogue holding a credential. Android's
/// `OpdsContributor` is its twin.
enum OpdsContributor {

    /// One feed page's entries as publications, and the feed's own `next` link.
    ///
    /// `sources`' *More from a source than the library holds*: the first read asks for the
    /// saved page's own url; `continueReadingCatalogues` asks every page after it for `url`
    /// in turn, each time the `next` this same function returned for the page before it --
    /// a catalogue is a chain the server hands forward one link at a time, and there is no
    /// offset or page number to ask for instead.
    struct Page {
        let slice: SourceSlice
        let next: URL?
    }

    /// `client` is the same seam `LibraryLookups.opdsCover(for:maxPixelSize:client:)` uses:
    /// nil builds the real one, ``ServerLibrary/client(for:)``'s own way, so a test can hand
    /// this a client built over a stubbed `URLSessionConfiguration` instead.
    static func page(
        source: UUID, page: CataloguePage, url: URL, client overridden: OpdsClient? = nil
    ) async throws -> Page {
        let client = overridden ?? ServerLibrary.client(for: page)
        let feed = try await client.feed(at: url, credential: page.credential)
        let publications = feed.publications.compactMap { publication(source: source, entry: $0) }
        return Page(slice: SourceSlice(publications: publications, holdsMore: feed.next != nil), next: feed.next)
    }

    /// One entry as a row, or nil for an entry that is not a publication.
    ///
    /// A feed's entries are not all books: a navigation entry is a way further in and has
    /// no acquisition at all. Those belong to the browser, not to the library.
    ///
    /// **The acquisition kind decides, not a substring match on the media type.** An entry
    /// whose only link is a loan or a subscription has nothing this app can fetch, and
    /// filing it as a row anyway — 11.5 — offered a download that failed the moment it was
    /// tapped. ``CatalogueAcquisition/readable(in:)`` already answers "what can the app
    /// act on", best format first; this asks it rather than re-deriving the answer here.
    static func publication(source: UUID, entry: OpdsEntry) -> Publication? {
        guard let acquisition = CatalogueAcquisition.readable(in: entry).first,
              let format = PublicationFormat(mediaType: acquisition.mediaType)
        else { return nil }
        return Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: source, remoteID: "opds:\(entry.id)")
            ),
            format: format,
            displayTitle: entry.title,
            series: entry.series,
            number: entry.seriesIndex.map { index in
                index.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(index))
                    : String(index)
            },
            authors: entry.authors,
            summary: entry.summary,
            origin: .authoritative,
            sourceID: source
        )
    }
}
