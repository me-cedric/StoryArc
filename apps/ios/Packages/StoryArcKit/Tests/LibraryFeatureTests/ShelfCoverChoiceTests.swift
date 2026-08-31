import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What the cover picker offers a collection, and which of them the collection is wearing.
///
/// `collections-and-reading-lists`: a collection's cover "is a composite of its first four
/// member covers unless the user sets a specific one". ``CompositeCover`` has always honoured
/// the second clause; until this picker existed nothing in either app could reach it, so the
/// clause was unreachable rather than merely untested.
///
/// The picker and the shelf card must never disagree about what is showing, which is why
/// ``ShelfCoverChoice/chosen(in:)`` answers from the same premise ``CompositeCover`` does
/// rather than from a flag of its own. Android's `ShelfCoverChoice` answers these identically.
@Suite("Shelf cover choice")
struct ShelfCoverChoiceTests {

    private func collection(
        _ members: Set<String>,
        cover: String? = nil
    ) -> PublicationCollection {
        PublicationCollection(name: "Image Comics", members: members, coverMemberID: cover)
    }

    @Test("The composite is always offered, and offered first")
    func compositeLeads() {
        #expect(ShelfCoverChoice.options(of: collection(["b", "a"])).first == .composite)
        #expect(ShelfCoverChoice.options(of: collection(["a"], cover: "a")).first == .composite)
    }

    /// The same order ``CompositeCover`` reads members in, so the four on the composite tile
    /// are visibly the first four of the row beneath it.
    @Test("Members are offered in identity order, the order the composite reads them in")
    func identityOrder() {
        let options = ShelfCoverChoice.options(of: collection(["delta", "alpha", "charlie"]))
        #expect(options == [.composite, .member("alpha"), .member("charlie"), .member("delta")])
    }

    @Test("A collection holding nothing has only the composite to offer")
    func emptyCollection() {
        #expect(ShelfCoverChoice.options(of: collection([])) == [.composite])
    }

    @Test("With no choice made, the composite is what is showing")
    func compositeByDefault() {
        #expect(ShelfCoverChoice.chosen(in: collection(["a", "b"])) == .composite)
    }

    @Test("A chosen member is what is showing, and is one of the options")
    func chosenMember() {
        let picked = collection(["a", "b"], cover: "b")
        #expect(ShelfCoverChoice.chosen(in: picked) == .member("b"))
        #expect(ShelfCoverChoice.options(of: picked).contains(.member("b")))
    }

    /// ``CompositeCover``'s own second guard: a cover that has left the collection is not the
    /// collection's cover any more. Answered the same way here, so the tick in the picker
    /// cannot land on a book the collection does not contain.
    @Test("A cover that is no longer a member falls back to the composite")
    func coverThatLeft() {
        #expect(ShelfCoverChoice.chosen(in: collection(["a"], cover: "gone")) == .composite)
    }

    /// The invariant that keeps the picker honest: whatever it says is showing is something
    /// it also offers, so there is always a way back to it.
    @Test("Whatever is showing is one of the options")
    func chosenIsOffered() {
        let cases = [
            collection([]),
            collection(["a", "b", "c", "d", "e"]),
            collection(["a", "b"], cover: "a"),
            collection(["a"], cover: "gone")
        ]
        for each in cases {
            #expect(ShelfCoverChoice.options(of: each).contains(ShelfCoverChoice.chosen(in: each)))
        }
    }
}
