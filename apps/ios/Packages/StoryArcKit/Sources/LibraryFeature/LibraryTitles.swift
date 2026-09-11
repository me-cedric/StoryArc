internal import SwiftUI

/// What the navigation bar calls the library, on each of its three surfaces and while a
/// selection is running.
///
/// Lifted out of `LibraryView.swift` when that file reached the length the linter allows and
/// the shelf gained the series-or-issues choice. Two computed properties and their
/// documentation, unchanged — the screen itself keeps its state, its body and its toolbar.
extension LibraryView {

    /// What the navigation bar calls this surface.
    var title: Text {
        switch surface {
        case .shelf: Text("library.title", bundle: .module)
        case .onDevice: Text("library.downloads.title", bundle: .module)
        case .search: Text("library.search.prompt", bundle: .module)
        }
    }

    /// What the navigation bar says instead, while a selection is running.
    ///
    /// The count, stated in the one place a reader is already looking for the name of what
    /// they are on. It is a plural in all four languages — `library.selected %lld` carries
    /// the variations — and it is stated at nought as well: the mode can be entered without
    /// picking anything, and a title that only appeared on the first pick would leave the
    /// navigation bar naming a shelf the reader has stopped browsing.
    var selectionTitle: Text {
        Text("library.selected \(selection.count)", bundle: .module)
    }
}
