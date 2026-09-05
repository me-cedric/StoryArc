import Foundation
import Testing

@testable import StoryArcCore

/// The shelves a reader pins to the home surface.
///
/// `home-screen`, *Pinned shelves*: a pinned collection or reading list "appears on the home
/// surface as a shelf of its own, ahead of the unpinned ones", and "unpinning it removes the
/// shelf without altering the collection or the list".
///
/// The second clause is a promise about something *not* happening, and it is kept by the
/// shape of the type rather than by care: a pin is a key held beside the shelves, so
/// unpinning has nothing to reach into. What is left to assert is the ordering, the round
/// trip through storage, and what happens to a token this version cannot read.
@Suite("Pinned shelves")
struct PinnedShelvesTests {

    private struct Shelf: Equatable {
        let name: String
        let pin: ShelfPin
    }

    private func collection(_ name: String, _ id: UUID = UUID()) -> Shelf {
        Shelf(name: name, pin: .collection(id))
    }

    private func list(_ name: String, _ id: UUID = UUID()) -> Shelf {
        Shelf(name: name, pin: .list(id))
    }

    @Test("A pinned shelf leads the rest")
    func pinnedComesFirst() {
        let shelves = [collection("Image"), list("Crossover"), collection("For bedtime")]
        let pinned = PinnedShelves().toggling(shelves[2].pin)

        #expect(
            pinned.ordering(shelves, by: \.pin).map(\.name)
                == ["For bedtime", "Image", "Crossover"]
        )
    }

    @Test("Pinning moves one shelf and reorders nothing else")
    func theRestKeepTheirOrder() {
        // The reader's own order survives inside each run. A sort would have been shorter and
        // would have reshuffled everything the first time two shelves compared equal.
        let shelves = [collection("A"), list("B"), collection("C"), list("D")]
        let pinned = PinnedShelves().toggling(shelves[3].pin).toggling(shelves[1].pin)

        #expect(pinned.ordering(shelves, by: \.pin).map(\.name) == ["B", "D", "A", "C"])
    }

    @Test("Nothing pinned leaves the list exactly as it was")
    func nothingPinnedChangesNothing() {
        let shelves = [collection("A"), list("B")]

        #expect(PinnedShelves().ordering(shelves, by: \.pin) == shelves)
        #expect(PinnedShelves().isEmpty)
    }

    @Test("Unpinning is the same action as pinning, and puts the shelf back where it was")
    func togglingIsOneAction() {
        let shelves = [collection("A"), list("B"), collection("C")]
        let once = PinnedShelves().toggling(shelves[2].pin)
        let twice = once.toggling(shelves[2].pin)

        #expect(once.contains(shelves[2].pin))
        #expect(!twice.contains(shelves[2].pin))
        #expect(twice.ordering(shelves, by: \.pin) == shelves)
    }

    @Test("A collection and a reading list that shared an identifier would not share a pin")
    func theKindIsPartOfTheKey() {
        // Not a thing that happens, and exactly the sort of not-a-thing that turns into a bug
        // nobody can reproduce. The two are different types for a reason the shelves file
        // argues at length; a pin that ignored which was which would quietly undo that.
        let id = UUID()
        let pinned = PinnedShelves().toggling(.collection(id))

        #expect(pinned.contains(.collection(id)))
        #expect(!pinned.contains(.list(id)))
    }

    @Test("A pin survives being written down and read back")
    func storedAsTokens() {
        let one = UUID()
        let other = UUID()
        let pinned = PinnedShelves().toggling(.collection(one)).toggling(.list(other))

        #expect(PinnedShelves(tokens: pinned.tokens) == pinned)
        // Sorted, so two runs that pinned the same shelves write the same value and a diff
        // of a preferences file is readable.
        #expect(pinned.tokens == pinned.tokens.sorted())
        #expect(PinnedShelves.storageKey == "app.storyarc.pinnedShelves")
    }

    @Test("The token names the kind in words, so a stored pin is readable and reorder-proof")
    func tokensAreNamed() {
        let id = UUID()

        #expect(ShelfPin.collection(id).token == "collection:\(id.uuidString)")
        #expect(ShelfPin.list(id).token == "list:\(id.uuidString)")
    }

    @Test("A token this version cannot read is dropped rather than guessed at")
    func unreadableTokensAreDropped() {
        // An unreadable pin drops one shelf off the home surface, which the reader can see
        // and put back. A guessed one pins a shelf they never chose and gives them nothing
        // to undo.
        let good = ShelfPin.collection(UUID())
        let restored = PinnedShelves(tokens: [good.token, "shelf:not-a-uuid", "list:", "", "nope"])

        #expect(restored.tokens == [good.token])
        #expect(ShelfPin(token: "collection:not-a-uuid") == nil)
        #expect(ShelfPin(token: "everything") == nil)
    }
}
