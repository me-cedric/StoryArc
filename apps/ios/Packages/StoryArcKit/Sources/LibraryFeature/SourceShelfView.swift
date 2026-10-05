internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// Which screen a source opened from the library is opened as.
///
/// Two screens and not one, because they answer different questions. *More from this
/// library* at the foot of the shelf asks for the rest of **this library**, which
/// `library-browsing` requires to be drawn by the library's own grid — see
/// ``SourceShelfView``. A search result and a refused source ask for the server's own
/// catalogue, which only ``SourceBrowser`` can walk.
///
/// One value carries both so the shelf still has exactly one navigation: a second
/// `@State` would be a second destination set, which is what ``LibraryPanes`` refuses.
enum SourceDestination: Hashable {
    /// The source's own rows, drawn by the shelf.
    case shelf(Source.ID)
    /// The source's own catalogue, walked page by page.
    case browser(Source.ID)

    /// Which source this leads to, whichever screen it leads to.
    var sourceID: Source.ID {
        switch self {
        case let .shelf(id), let .browser(id): id
        }
    }
}

/// One source's publications, in the library's own arrangement.
///
/// A free function beside the view rather than a method on it, so the rule is testable
/// without a window — the same reason ``seriesShelfMembers(named:in:)`` is one.
/// ``LibraryScope/contains(_:)`` is what narrows it, so a publication no source claims is
/// left out here by the same rule that leaves it out of the by-library filter.
///
/// The arrangement is the library's default rather than the reader's current one: this
/// screen carries no sort control and no filter, because it is the library narrowed to one
/// source and not a second library with choices of its own. Android's `sourceShelfMembers`
/// is its twin.
func sourceShelfMembers(of sourceID: UUID, in publications: [Publication]) -> [Publication] {
    LibraryIndex.arrange(publications, query: LibraryQuery(scope: .source(sourceID)))
}

/// Everything one source has put in the library, drawn by the shelf's own grid.
///
/// `library-browsing`, *More from a source than the library holds*: what a source holds
/// beyond the slice the first read took is reachable from "an explicit *more from this
/// library* affordance at the foot of the shelf", and those publications "are rendered by
/// the same grid, the same cells and the same publication page as everything else". The
/// footer used to open ``SourceBrowser``, which draws a catalogue with cells of its own —
/// the one clause of that scenario the affordance did not meet.
///
/// **No pager of its own, deliberately.** ``ServerLibrary/continueReadingServers()``
/// already reads a partial source's later pages and adopts each one as an ordinary library
/// row, so the rest of the library arrives here by itself. Reading the library rather than
/// being handed a list is also what lets a source still answering fill the screen in as it
/// goes, which is the reason ``SeriesShelfView`` reads it too.
///
/// A cover reaches the publication page because this screen is pushed into the column that
/// registers ``SwiftUI/View/publicationPages(in:onOpen:onListen:)`` — ``LibraryPanes``
/// explains why that column and not the other. Android's `SourceShelfScreen` is its twin.
struct SourceShelfView: View {
    let source: Source
    let model: LibraryModel

    @Environment(\.theme) private var theme

    var body: some View {
        // `library-browsing`: a series "is listed once, as a single cell". The library's own
        // rule, asked here as well, because a cell here and a cell on the shelf have to mean
        // the same thing to a reader who has learned one of them.
        let rows = LibraryRows.of(sourceShelfMembers(of: source.id, in: model.publications))
        CoverGrid(
            publications: rows.map(\.lead),
            model: model,
            seriesRows: Dictionary(uniqueKeysWithValues: rows.compactMap { row in
                guard case .series = row else { return nil }
                return (row.lead.id, row)
            })
        )
        .background(theme.palette.surfaceCanvas)
        .navigationTitle(source.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
