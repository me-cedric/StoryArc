internal import SwiftUI

internal import StoryArcCore

/// What a shelf's context menu offers: pin it to Home, or delete it.
///
/// Split out of `ShelvesView.swift` when adding the pin took that file past the 400 lines
/// the linter allows. The two belong together — they are the whole of one menu, and the
/// order between them is a decision one of them explains — so this is a seam rather than an
/// arbitrary cut at the line count.
extension ShelvesView {

    /// Pin this shelf to the home surface, or take it off again.
    ///
    /// `home-screen`, *Pinned shelves*. One control that reads the state it is in rather
    /// than two: a menu carrying both *Pin* and *Unpin* would make a reader read both to
    /// find out which one applies to the shelf they long-pressed.
    ///
    /// Above *Delete* and not beside it, because a context menu puts its destructive item
    /// last and an ordinary action above it — and because pinning is the one a reader will
    /// reach for repeatedly and deleting is the one they should have to aim at.
    ///
    /// **Server-backed shelves have no pin, and that is a gap rather than a decision.** They
    /// arrive as `ServerShelf` values fetched per visit rather than as
    /// ``PublicationCollection``s the app holds, so the only identity they have is the
    /// server's own numbering — and ``ShelfPin`` is deliberately a `UUID`, for the reason
    /// ``ShelfKey`` exists: two Kavita servers number their reading lists from one. Pinning
    /// one would need a third case carrying a `ShelfKey`, and a home surface that resolved it
    /// would have to ask a server — which `home-screen`'s *The home surface never waits on a
    /// source* forbids outright. Named in this change's task 2.1 rather than papered over.
    @ViewBuilder
    func pinButton(_ pin: ShelfPin) -> some View {
        let pinned = PinnedShelves(stored: pinnedShelves)
        Button {
            pinnedShelves = pinned.toggling(pin).stored
        } label: {
            Label {
                Text(pinned.contains(pin) ? "shelves.unpin" : "shelves.pin", bundle: .module)
            } icon: {
                Image(systemName: pinned.contains(pin) ? "pin.slash" : "pin")
            }
        }
    }

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
}
