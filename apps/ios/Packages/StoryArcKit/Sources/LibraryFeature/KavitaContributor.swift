import Foundation
import Kavita
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
    /// One request for the page, then one per series for its chapters — so this number is
    /// the request count, near enough. A starting value chosen to be re-chosen.
    static let firstSlice = 60

    /// The chapters of a server's most recently added series, as publications.
    ///
    /// A series whose chapters cannot be read is skipped rather than failing the round.
    static func publications(source: UUID, client: KavitaClient) async throws -> SourceSlice {
        let series = try await client.recentSeries(page: 1, size: firstSlice)
        var found: [Publication] = []
        for each in series {
            let volumes = (try? await client.volumes(ofSeries: each.id)) ?? []
            for chapter in volumes.flatMap(\.chapters) {
                found.append(publication(source: source, series: each, chapter: chapter))
            }
        }
        // A full page is the only evidence a server has more, and it is evidence rather
        // than proof: a library of exactly sixty series reads as partial once, and says so
        // until the page comes back short. Overstating what is held back is the safe way
        // round — the other way tells a reader their five-thousand-title server has 137.
        return SourceSlice(publications: found, holdsMore: series.count >= firstSlice)
    }

    /// One chapter as a row in the library.
    ///
    /// No path, which is the whole of what makes it a remote row: nothing is on disk, so
    /// the cover resolver and the availability axis both read it as needing its source.
    static func publication(
        source: UUID,
        series: KavitaSeries,
        chapter: KavitaChapter
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: source, remoteID: "chapter:\(chapter.id)")
            ),
            format: format(series.format),
            displayTitle: title(series: series, chapter: chapter),
            series: series.name,
            number: issueNumber(of: chapter),
            origin: .authoritative,
            pageCount: chapter.pages > 0 ? chapter.pages : nil,
            sourceID: source
        )
    }

    /// What to call one chapter.
    ///
    /// Three cases, and the first two were wrong before this. A chapter with a title of
    /// its own keeps it. A numbered one reads `<series> #<number>`, the house format,
    /// because a cell headed "43" names nothing. And Kavita writes `-100000` for a chapter
    /// with no number at all, which is not a number and leaves the series' own name.
    private static func title(series: KavitaSeries, chapter: KavitaChapter) -> String {
        if let named = chapter.title, !named.isEmpty { return named }
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
