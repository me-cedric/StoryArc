import Foundation
import StoryArcCore

/// The ids, the index and the division of a shelf, worked out once for a shelf, a sort and a
/// width rather than on every pass of the view.
///
/// Measured on a grid of 5,000 publications (`desktop-budgets-macos.md`, task 5.10): the grid's
/// body ran ``ShelfSections/index(_:sort:locale:)`` and ``ShelfSections/divide(_:by:columns:locale:)``
/// on each pass, each a collation key per title, and a resize passes once a frame. Each cell also
/// mapped the whole shelf to its ids for the selection's order. Held in a view's `@State`, so a
/// pass that changes neither the shelf nor the width reads the last answer.
@MainActor
final class ShelfLayoutMemo {
    private struct ShelfKey: Equatable {
        let publications: [Publication]
        let sort: LibrarySort
        let divides: Bool
    }

    private struct SectionsKey: Equatable {
        let shelf: ShelfKey
        let columns: Int
    }

    private var shelfKey: ShelfKey?
    private var shelf: (ids: [String], index: [ShelfIndexEntry]) = ([], [])
    private var sectionsKey: SectionsKey?
    private var sections: [ShelfSection] = []

    /// The shelf's ids in its order, and its index when it may be indexed.
    func shelf(
        _ publications: [Publication], sort: LibrarySort, divides: Bool
    ) -> (ids: [String], index: [ShelfIndexEntry]) {
        let key = ShelfKey(publications: publications, sort: sort, divides: divides)
        if key != shelfKey {
            shelfKey = key
            shelf = (
                publications.map(\.id),
                divides ? ShelfSections.index(publications, sort: sort, locale: .storyArc) : []
            )
        }
        return shelf
    }

    /// The shelf divided for `columns` cells across, or nothing when it may not be divided.
    func sections(
        _ publications: [Publication], sort: LibrarySort, divides: Bool, columns: Int
    ) -> [ShelfSection] {
        let shelf = ShelfKey(publications: publications, sort: sort, divides: divides)
        let key = SectionsKey(shelf: shelf, columns: columns)
        if key != sectionsKey {
            sectionsKey = key
            sections = divides
                ? ShelfSections.divide(publications, by: sort, columns: columns, locale: .storyArc) : []
        }
        return sections
    }
}
