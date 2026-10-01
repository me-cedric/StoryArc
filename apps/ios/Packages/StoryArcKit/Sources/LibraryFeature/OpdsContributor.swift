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
