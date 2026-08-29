import Foundation
import Testing

@testable import Persistence
@testable import StoryArcCore

/// Mirrors Android's `AnnotationStoreTest`, assertion for assertion.
@Suite("Annotations")
struct AnnotationStoreTests {

    private func store() throws -> (AnnotationStore, UserDefaults) {
        let defaults = try #require(UserDefaults(suiteName: "annotations-\(UUID().uuidString)"))
        return (AnnotationStore(defaults: defaults), defaults)
    }

    private func mark(
        id: UUID = UUID(),
        _ text: String = "Call me Ishmael",
        note: String = "",
        colour: HighlightColour = .yellow,
        at progression: Double = 0.25
    ) -> Annotation {
        Annotation(
            id: id, locator: "{}", resource: "ch1.xhtml", progression: progression,
            chapter: "Chapter One", text: text, colour: colour, note: note,
            createdAt: Date(timeIntervalSince1970: progression * 1000)
        )
    }

    @Test("A highlight is kept with its words and its colour")
    func keepsTheMark() throws {
        let (store, _) = try store()
        store.save(mark(colour: .green), in: "book")

        let kept = try #require(store.annotations(for: "book").first)
        #expect(kept.text == "Call me Ishmael")
        #expect(kept.colour == .green)
        #expect(!kept.hasNote)
    }

    @Test("Writing on a highlight replaces it rather than making a second one")
    func editingReplaces() throws {
        let (store, _) = try store()
        let id = UUID()
        store.save(mark(id: id), in: "book")
        store.save(mark(id: id, note: "The famous opening"), in: "book")

        let marks = store.annotations(for: "book")
        #expect(marks.count == 1)
        #expect(marks.first?.note == "The famous opening")
    }

    @Test("Two marks on different words are two marks")
    func distinctMarksAreKept() throws {
        let (store, _) = try store()
        store.save(mark("first", at: 0.1), in: "book")
        store.save(mark("second", at: 0.2), in: "book")

        #expect(store.annotations(for: "book").count == 2)
    }

    @Test("The list reads in book order, not in the order the marks were made")
    func ordersByPosition() throws {
        let (store, _) = try store()
        store.save(mark("later", at: 0.9), in: "book")
        store.save(mark("earlier", at: 0.1), in: "book")

        #expect(store.annotations(for: "book").map(\.text) == ["earlier", "later"])
    }

    @Test("One publication's marks are not another's")
    func keepsPublicationsApart() throws {
        let (store, _) = try store()
        store.save(mark(), in: "one")

        #expect(store.annotations(for: "two").isEmpty)
    }

    @Test("Removing the last mark leaves nothing behind for that publication")
    func removesByIdentity() throws {
        let (store, _) = try store()
        let only = mark()
        store.save(only, in: "book")

        #expect(store.remove(only.id, from: "book").isEmpty)
    }

    @Test("Marks survive being read back through a second store")
    func survivesReopening() throws {
        let (store, defaults) = try store()
        store.save(mark(note: "kept"), in: "book")

        let reopened = AnnotationStore(defaults: defaults).annotations(for: "book")
        #expect(reopened.first?.note == "kept")
    }

    @Test("Clearing a publication takes its marks and leaves the others")
    func clearsOnePublication() throws {
        let (store, _) = try store()
        store.save(mark(), in: "one")
        store.save(mark(), in: "two")
        store.clear("one")

        #expect(store.annotations(for: "one").isEmpty)
        #expect(store.annotations(for: "two").count == 1)
    }
}
