import Foundation
import Kavita
internal import Persistence
import StoryArcCore

/// What a Kavita server puts in the library.
///
/// `library-browsing` requires one library over every source. Until this, only a folder
/// scan reached the grid, so a reader with a server saw the files on their device and
/// nothing else.
///
/// **A chapter is the publication, not a series.** A row in the library is something a
/// reader opens, and a series opens a list — which is what the browser already is. A
/// chapter is also what everything downstream keys on: a position is recorded against one,
/// a download fetches one, and a server identifier wants a remote id naming something
/// fetchable. The *cell* is still one per series; ``LibraryRows`` decides that, from these.
///
/// **The first read is a slice, newest first.** A server with forty thousand series is
/// minutes of requests. What is not in the slice stays reachable through search and the
/// server's own browser, which is what *More from a source than the library holds*
/// requires. Android's `KavitaContributor` is its twin.
enum KavitaContributor {

    /// How many series the first read of a server takes.
    ///
    /// One request for the page, then two per series, for its chapters and its status — so
    /// this number is half the request count, near enough. A starting value chosen to be re-chosen.
    static let firstSlice = 60

    /// One page of a server's most recently added series, as publications, and how many
    /// series that page held.
    ///
    /// `sources`' *More from a source than the library holds*: the first read is
    /// ``publications(source:client:)``, page one, and ``LibraryModel/continueReading()``
    /// asks for every page after it the same way, so there is one function that knows how a
    /// Kavita page becomes a slice rather than the first read and the continuation each
    /// carrying their own copy of it.
    ///
    /// A series whose chapters cannot be read is skipped rather than failing the round.
    struct Page {
        let slice: SourceSlice
        /// Series read in this page, which is what the source detail screen counts —
        /// distinct from `slice.publications.count`, a chapter total that means nothing to
        /// a reader who thinks of a library in series.
        let seriesRead: Int
        /// The chapters this page read, each still carrying the server's own `pagesRead`.
        ///
        /// What ``KavitaSync/pull(_:in:into:of:to:)`` needs, and what building
        /// ``slice`` already asked every one of these series for — the library's own
        /// refresh of a source is a pull's other caller, and it has no reason to ask
        /// the server the same question twice.
        let chapters: [KavitaChapter]
    }

    static func page(
        source: UUID,
        client: KavitaClient,
        page: Int,
        store: KavitaProgressStore = KavitaProgressStore()
    ) async throws -> Page {
        let series = try await client.recentSeries(page: page, size: firstSlice)
        var found: [Publication] = []
        var chapters: [KavitaChapter] = []
        // Every chapter this read sees, so a reading list or a mark reaches Kavita for a
        // row the reader has only ever seen on a shelf — see ``KavitaProgressStore/rememberCatalog(_:)``.
        var origins: [String: KavitaOrigin] = [:]
        for each in series {
            let volumes = (try? await client.volumes(ofSeries: each.id)) ?? []
            let status = volumes.isEmpty ? nil : await seriesStatus(client: client, series: each.id)
            for volume in volumes {
                for chapter in volume.chapters {
                    found.append(publication(source: source, series: each, chapter: chapter, status: status))
                    chapters.append(chapter)
                }
                origins.merge(catalogOrigins(source: source, series: each, volume: volume)) { _, new in new }
            }
        }
        store.rememberCatalog(origins)
        // A full page is the only evidence a server has more, and it is evidence rather
        // than proof: a library of exactly sixty series reads as partial once, and says so
        // until the page comes back short. Overstating what is held back is the safe way
        // round — the other way tells a reader their five-thousand-title server has 137.
        return Page(
            slice: SourceSlice(publications: found, holdsMore: series.count >= firstSlice),
            seriesRead: series.count,
            chapters: chapters
        )
    }

    /// The chapters of a server's most recently added series, as publications.
    static func publications(
        source: UUID,
        client: KavitaClient,
        store: KavitaProgressStore = KavitaProgressStore()
    ) async throws -> Page {
        try await page(source: source, client: client, page: 1, store: store)
    }

    /// The status the server reports for one series, or `nil` when it could not be read.
    ///
    /// `library-browsing` (D36): the status a source reports is carried onto the row, so the
    /// filter covers a server's series and not only the ones a reader downloaded. One more
    /// request per series that has chapters. A failure costs the row its status, never the
    /// row: the series screen then treats it as a series with no reported status.
    static func seriesStatus(client: KavitaClient, series id: Int) async -> PublicationStatus? {
        PublicationStatus(kavita: (try? await client.metadata(ofSeries: id))?.publicationStatus)
    }

    /// One chapter as a row in the library.
    ///
    /// No path, which is the whole of what makes it a remote row: nothing is on disk, so
    /// the cover resolver and the availability axis both read it as needing its source.
    static func publication(
        source: UUID,
        series: KavitaSeries,
        chapter: KavitaChapter,
        status: PublicationStatus? = nil
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: source, remoteID: "chapter:\(chapter.id)")
            ),
            format: format(series.format),
            displayTitle: title(series: series, chapter: chapter),
            series: series.name,
            number: issueNumber(of: chapter),
            status: status,
            origin: .authoritative,
            pageCount: chapter.pages > 0 ? chapter.pages : nil,
            sourceID: source
        )
    }

    /// Where each of a volume's chapters sits on the server, keyed by the row it becomes.
    ///
    /// The rule ``page(source:client:page:store:)`` needs and a test can reach without a
    /// server: given a series and one of its volumes, which is what a browse already holds
    /// by the time it has either, this is every chapter's full address — library, series,
    /// volume, chapter — filed under the same key ``Publication/id`` gives the row. Lifted
    /// out so ``KavitaContributorCatalogOriginTests`` can prove it without a stub.
    static func catalogOrigins(
        source: UUID,
        series: KavitaSeries,
        volume: KavitaVolume
    ) -> [String: KavitaOrigin] {
        var result: [String: KavitaOrigin] = [:]
        for chapter in volume.chapters {
            let row = publication(source: source, series: series, chapter: chapter)
            result[row.id] = KavitaOrigin(
                sourceId: source.uuidString,
                libraryId: series.libraryId,
                seriesId: series.id,
                volumeId: volume.id,
                chapterId: chapter.id,
                pages: chapter.pages
            )
        }
        return result
    }

    /// What to call one chapter.
    ///
    /// Three cases, and the first two were wrong before this. A chapter with a title of
    /// its own keeps it. A numbered one reads `<series> #<number>`, the house format,
    /// because a cell headed "43" names nothing. And Kavita writes `-100000` for a chapter
    /// with no number at all, which is not a number and leaves the series' own name.
    private static func title(series: KavitaSeries, chapter: KavitaChapter) -> String {
        if let named = chapter.properTitle { return named }
        // `<series> #<number>`, the house format `seriesLine` composes, so a server's issue
        // and a scanned one read the same. The bare number was the bug: a shelf of cells
        // headed "43" names nothing.
        if let number = issueNumber(of: chapter) { return "\(series.name) #\(number)" }
        return series.name
    }

    /// The chapter's issue number, where it has one.
    ///
    /// The same question ``title(series:chapter:)`` asks, and it has to be the same answer:
    /// `Publication.number` is drawn on its own as `#<number>` under a row, so a sentinel
    /// stored here comes back beside a title that had correctly left it out — a row reading
    /// the series' name over a line reading that name and "#-100000".
    ///
    /// Kavita writes `-100000` for a chapter with no number at all: a collected edition, or
    /// a volume with one part. Any negative is treated the same way, because none of them is
    /// an issue number.
    /// `KavitaChapter.issueNumber` is where the rule lives now — every screen that draws a
    /// chapter needs the same answer, and one that asked separately is how "-100000"
    /// reached a chapter list while the shelf was already guarded against it.
    static func issueNumber(of chapter: KavitaChapter) -> String? { chapter.issueNumber }

    /// The title a reader sees, for a chapter kept as a download as well as for a row.
    static func title(of chapter: KavitaChapter, in series: KavitaSeries) -> String {
        title(series: series, chapter: chapter)
    }

    /// Kavita's `MangaFormat` as this app's own.
    ///
    /// A guess with one visible consequence, stated rather than hidden: Kavita says
    /// "archive", not which archive, so every comic on a server files as CBZ until it is
    /// downloaded. A format the filter cannot show would be worse — a reader filtering for
    /// comics would lose the server's whole catalogue.
    private static func format(_ kavita: Int) -> PublicationFormat {
        switch kavita {
        case 0: .imageFolder
        case 3: .epub
        case 4: .pdf
        default: .cbz
        }
    }
}
