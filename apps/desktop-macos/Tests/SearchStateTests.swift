import Foundation
import LibraryFeature
import StoryArcCore
import Testing

@testable import StoryArc

/// The query state of task 2.23b: the field stays, the results take the column, and the
/// filters and sort map onto the shared query.
@Suite("Search state")
struct SearchStateTests {
    @Test("Typing takes the content column; clearing returns to where the reader came from")
    func resultsTakeTheColumn() {
        let onLibrary = SearchState().moved(to: .library)
        #expect(onLibrary.shownDestination == .library)

        let typed = onLibrary.typed("saga")
        #expect(typed.isShowingResults)
        #expect(typed.shownDestination == nil)

        let wandered = typed.moved(to: .onDevice)
        let cleared = wandered.cleared()
        #expect(!cleared.isShowingResults)
        #expect(cleared.shownDestination == .library)
        #expect(cleared.text.isEmpty)
    }

    @Test("Spaces alone do not open the results")
    func whitespace() {
        #expect(!SearchState().typed("   ").isShowingResults)
    }

    @Test("The search joins the query without touching the filters or the sort")
    func appliedToQuery() {
        var query = LibraryQuery()
        query.formats = [.cbz]
        query.sort = .year
        query.ascending = false

        let applied = SearchState().typed("saga").applied(to: query)

        #expect(applied.search == "saga")
        #expect(applied.formats == [.cbz])
        #expect(applied.sort == .year && !applied.ascending)
    }

    @Test("Filters toggle by format, source and reading state")
    func filters() {
        var query = LibraryQuery()
        query = LibraryMenus.toggling(PublicationFormat.cbz, in: query)
        query = LibraryMenus.toggling(ReadState.finished, in: query)
        #expect(query.formats == [.cbz] && query.readStates == [.finished])
        query = LibraryMenus.toggling(PublicationFormat.cbz, in: query)
        #expect(query.formats.isEmpty)
        let scoped = LibraryMenus.scoping(.source(UUID()), in: query)
        #expect(scoped.scope != .allSources)
    }

    @Test("Sort keys apply, and choosing the current one again flips the direction")
    func sorts() {
        var query = LibraryQuery()
        query = LibraryMenus.sorting(by: .lastRead, in: query)
        #expect(query.sort == .lastRead && query.ascending)
        query = LibraryMenus.sorting(by: .lastRead, in: query)
        #expect(!query.ascending)
        query = LibraryMenus.sorting(by: .title, in: query)
        #expect(query.sort == .title && query.ascending)
        #expect(LibraryMenus.sorts.count == LibrarySort.allCases.count)
    }
}
