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

/// The screen that offers the choice, and the model call the choice reaches.
///
/// The picker answering its own questions proves nothing about whether a reader can open it:
/// `settingCover` and `coverMemberID` were round-tripped by the store and honoured by
/// ``StoryArcCore/CompositeCover`` for weeks while no view, view model or menu called any of
/// them, so a symbol search looked convincing and the clause was still unreachable. These
/// walk the built value tree of the screen the offer lives on. Android's
/// `ShelfCoverMenuTest` asks the same screen's semantics tree for the same control.
@MainActor
@Suite("The collection screen offers a cover")
struct ShelfCoverMenuTests {

    /// A model with one collection, kept in memory: no store is passed, so nothing here
    /// writes to the machine the test runs on.
    private func model(holding members: Set<String>) throws -> (LibraryModel, UUID) {
        let model = LibraryModel()
        model.create(collection: "Image Comics")
        let id = try #require(model.shelves.collections.first?.id)
        if !members.isEmpty { model.add(members, toCollection: id) }
        return (model, id)
    }

    @Test("A collection holding something offers the cover choice")
    func offersTheChoice() throws {
        let (model, id) = try model(holding: ["a", "b"])

        let drawn = ShelfCoverMenuTests.strings(in: CollectionDetail(model: model, id: id).body)

        #expect(
            drawn.contains("shelves.cover"),
            "the collection screen offers no way to choose a cover, so settingCover is unreachable again"
        )
    }

    @Test("A collection holding nothing does not offer it")
    func emptyOffersNothing() throws {
        let (model, id) = try model(holding: [])

        let drawn = ShelfCoverMenuTests.strings(in: CollectionDetail(model: model, id: id).body)

        #expect(!drawn.contains("shelves.cover"))
    }

    /// Choosing reaches the model, and the model reaches ``StoryArcCore/Shelves``.
    /// `ShelvesStoreTests` carries the same choice through a round trip on disk.
    @Test("The chosen cover is the one the collection then wears")
    func choosingSets() throws {
        let (model, id) = try model(holding: ["a", "b"])

        model.setCover("b", onCollection: id)

        #expect(model.shelves.collections.first?.coverMemberID == "b")
        #expect(ShelfCoverChoice.chosen(in: try #require(model.shelves.collections.first)) == .member("b"))
    }

    /// The walk `SourceDetailSizeTests` describes: depth capped, class instances visited
    /// once, and every claim made from it positive.
    private static func strings(in root: Any) -> Set<String> {
        var found: Set<String> = []
        var seen: Set<ObjectIdentifier> = []

        func walk(_ value: Any, depth: Int) {
            guard depth < 40 else { return }
            if let text = value as? String {
                found.insert(text)
                return
            }
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .class,
               !seen.insert(ObjectIdentifier(value as AnyObject)).inserted {
                return
            }
            for child in mirror.children { walk(child.value, depth: depth + 1) }
        }

        walk(root, depth: 0)
        return found
    }
}
