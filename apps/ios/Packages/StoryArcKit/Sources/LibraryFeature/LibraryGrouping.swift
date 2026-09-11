internal import SwiftUI

/// Whether the shelf presents a series as one cell, or every issue as its own row.
///
/// `library-browsing`'s *A series is one row* scenario describes the first, and its *A shelf
/// of issues* scenario describes the second. The library already holds one `Publication` per
/// issue and groups them for display, so this decides a presentation over data the app
/// already has — never a second fetch, and never a second store.
///
/// **Two cases, not two more cases on `LibraryLayout`.** Grid-or-list and series-or-issues
/// are two axes, and one enum of four states would make the next layout question a multiple
/// of this one.
///
/// Held by ``LibraryView`` rather than by `LibraryQuery`, exactly as ``LibraryAvailability``
/// is and for the same reason: the query is the contract both platforms share, and adding a
/// case to it is a change to `StoryArcCore` and to Android's mirror of it. This is one shelf
/// choice with a `UserDefaults` key of its own. Android keeps the same two answers in
/// `LibraryGrouping.kt`.
enum LibraryGrouping: String, CaseIterable, Sendable {
    /// A series is one cell, carrying its own artwork and how many publications it holds.
    ///
    /// First in the list and the default, because the owner reversed the first build to get
    /// it: a library of sixty series of twenty issues is twelve hundred cells otherwise.
    case series
    /// Every publication is its own cell, the ones a series held included.
    case issues

    /// Whether this answer collapses a series into one cell.
    ///
    /// The whole rule, in one place, so both platforms can assert it rather than read it off
    /// a menu. ``LibraryView/rows`` asks it, and Android's `rememberShelfRows` asks its twin.
    var isCollapsing: Bool { self == .series }

    /// What the choice is called on screen, inside the menu that holds the other view
    /// choices.
    var titleKey: LocalizedStringKey {
        switch self {
        case .series: "library.grouping.series"
        case .issues: "library.grouping.issues"
        }
    }

    /// Where the choice is written down.
    ///
    /// Its own key in the same `UserDefaults` the rest of the library's preferences use, for
    /// ``LibraryAvailability/storageKey``'s reason: this is not on the query, so it carries
    /// its own. One key for the whole library rather than one per scope — the layout is per
    /// scope because a dense list suits one library and not another, and how a reader wants a
    /// series presented is a habit instead.
    static let storageKey = "app.storyarc.libraryGrouping"
}
