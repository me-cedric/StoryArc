internal import Foundation
internal import SwiftUI

internal import StoryArcCore

// What a shelf's context menu offers: pin it to Home, rename it, or delete it.
//
// Split out of `ShelvesView.swift` when adding the pin took that file past the 400 lines the
// linter allows. They belong together — they are the whole of one menu, and the order between
// them is a decision one of them explains — so this is a seam rather than an arbitrary cut at
// the line count.

/// How one of a server's shelves is pinned, or `nil` for a source whose identifier this
/// device cannot read back as a `UUID`.
///
/// `nil` rather than a guess, for ``ShelfPin/init(token:)``'s reason: a row with no pin
/// offers no pin control, which the reader can see, where a guessed one would pin a shelf
/// they never chose. The triple is ``RememberedShelf``'s own, so the pin a reader sets here
/// is the pin the home surface reads back.
func serverShelfPin(_ shelf: ServerShelf) -> ShelfPin? {
    UUID(uuidString: shelf.server.id).map {
        .server(shelf.isList ? .readingList : .collection, sourceID: $0, serverID: shelf.id)
    }
}

/// Pin this shelf to the home surface, or take it off again.
///
/// `home-screen`, *Pinned shelves*. One control that reads the state it is in rather than
/// two: a menu carrying both *Pin* and *Unpin* would make a reader read both to find out
/// which one applies to the shelf they long-pressed.
///
/// Above *Delete* and not beside it, because a context menu puts its destructive item last
/// and an ordinary action above it — and because pinning is the one a reader will reach for
/// repeatedly and deleting is the one they should have to aim at.
///
/// **A server's shelf takes the same pin**, because `collections-and-reading-lists` says it
/// is "the same kind of object as locally created ones". It took a third ``ShelfPin`` case
/// to say so: the other two are a `UUID` this device minted, and a server shelf's only name
/// is its server's own numbering, which two servers reuse. ``RememberedShelf`` already
/// writes that triple down and survives a relaunch, so the home surface resolves the pin
/// from its own record rather than by asking a server — which `home-screen`'s *The home
/// surface never waits on a source* forbids outright.
///
/// Free rather than a ``ShelvesView`` method, so ``serverShelfCell(_:pending:model:deleting:pinned:destination:)``
/// can draw it as well; the stored scalar is handed in because `@AppStorage` lives on the
/// view that owns the screen.
@ViewBuilder
func pinButton(_ pin: ShelfPin, in pinned: Binding<String>) -> some View {
    let shelves = PinnedShelves(stored: pinned.wrappedValue)
    Button {
        pinned.wrappedValue = shelves.toggling(pin).stored
    } label: {
        Label {
            Text(shelves.contains(pin) ? "shelves.unpin" : "shelves.pin", bundle: .module)
        } icon: {
            Image(systemName: shelves.contains(pin) ? "pin.slash" : "pin")
        }
    }
}

extension ShelvesView {

    @ViewBuilder
    func deleteButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Label {
                Text("shelves.delete", bundle: .module)
            } icon: {
                Image(systemName: "trash")
            }
        }
    }

    /// Task 7.10: an ordinary action beside the destructive one, the same order `pinButton`
    /// keeps above `deleteButton`.
    @ViewBuilder
    func renameButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text("shelves.rename", bundle: .module)
            } icon: {
                Image(systemName: "pencil")
            }
        }
    }
}
