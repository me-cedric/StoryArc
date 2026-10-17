import LibraryFeature
import StoryArcCore

/// The state behind the toolbar's search field and its menus.
///
/// `desktop-experience`, *Search on a desktop*: the field stays in the toolbar, its results
/// take over the content column while text is in it, and clearing it returns the column to
/// the destination the reader came from. The filters and the sort are the shared
/// `LibraryQuery`'s, so the Mac narrows and orders the shelf by the same rules as the
/// phone. Task 2.23b.
struct SearchState: Equatable, Sendable {
    private(set) var text = ""
    /// Where the reader was when the search began, to go back to.
    private(set) var cameFrom: LibraryDestination = .home
    private(set) var destination: LibraryDestination = .home

    /// Whether the results view has the content column.
    var isShowingResults: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

    /// What the column shows: the results, or the destination the reader is on.
    var shownDestination: LibraryDestination? { isShowingResults ? nil : destination }

    func typed(_ text: String) -> SearchState {
        var next = self
        if !isShowingResults, !text.trimmingCharacters(in: .whitespaces).isEmpty {
            next.cameFrom = destination
        }
        next.text = text
        return next
    }

    /// Escape or an emptied field: back to where the reader came from, the field in place.
    func cleared() -> SearchState {
        var next = self
        next.text = ""
        next.destination = cameFrom
        return next
    }

    func moved(to destination: LibraryDestination) -> SearchState {
        var next = self
        next.destination = destination
        if !isShowingResults { next.cameFrom = destination }
        return next
    }

    /// The query with this search applied and the reader's filters and sort kept.
    func applied(to query: LibraryQuery) -> LibraryQuery {
        var next = query
        next.search = text
        return next
    }
}

/// The filters and sorts the toolbar menus offer, mapped onto the shared query.
enum LibraryMenus {
    static let sorts: [LibrarySort] = [.title, .series, .lastRead, .progress, .year, .dateAdded, .fileSize]
    static let readStates: [ReadState] = [.unread, .inProgress, .finished]

    static func toggling(_ format: PublicationFormat, in query: LibraryQuery) -> LibraryQuery {
        var next = query
        if next.formats.contains(format) { next.formats.remove(format) } else { next.formats.insert(format) }
        return next
    }

    static func toggling(_ state: ReadState, in query: LibraryQuery) -> LibraryQuery {
        var next = query
        if next.readStates.contains(state) { next.readStates.remove(state) } else { next.readStates.insert(state) }
        return next
    }

    static func scoping(_ scope: LibraryScope, in query: LibraryQuery) -> LibraryQuery {
        var next = query
        next.scope = scope
        return next
    }

    /// Choosing the current sort again flips its direction, as a table column does.
    static func sorting(by sort: LibrarySort, in query: LibraryQuery) -> LibraryQuery {
        var next = query
        if next.sort == sort {
            next.ascending.toggle()
        } else {
            next.sort = sort
            next.ascending = true
        }
        return next
    }
}
