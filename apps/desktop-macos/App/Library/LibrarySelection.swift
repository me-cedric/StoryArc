import Foundation

/// Which publications are selected in the grid or the list.
///
/// `docs/designs/desktop/macos.md` section 3: a click selects one, Command-click adds or
/// removes one, Shift-click extends from the anchor through the visible order. Pure, so
/// `LibraryViewModelTests` holds the rules without a window. Task 2.23a.
struct LibrarySelection: Equatable, Sendable {
    private(set) var ids: Set<String> = []
    private(set) var anchor: String?

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    /// A plain click: this one and no other.
    func clicked(_ id: String) -> LibrarySelection {
        LibrarySelection(ids: [id], anchor: id)
    }

    /// Command-click: toggles membership. Adding moves the anchor there; removing leaves it
    /// on the last one added, as a table view in AppKit does.
    func commandClicked(_ id: String) -> LibrarySelection {
        var next = self
        if next.ids.contains(id) {
            next.ids.remove(id)
        } else {
            next.ids.insert(id)
            next.anchor = id
        }
        return next
    }

    /// Shift-click: everything between the anchor and this one in `order`, added.
    func shiftClicked(_ id: String, order: [String]) -> LibrarySelection {
        guard let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) else {
            return clicked(id)
        }
        var next = self
        next.ids.formUnion(order[min(from, to)...max(from, to)])
        return next
    }

    func cleared() -> LibrarySelection { LibrarySelection() }

    /// The selection with publications that left the shelf dropped.
    func kept(in order: [String]) -> LibrarySelection {
        var next = self
        next.ids = ids.intersection(order)
        if let anchor, !order.contains(anchor) { next.anchor = nil }
        return next
    }
}
