import Foundation
import Testing

@testable import Persistence
@testable import StoryArcCore

@Suite("Bookmarks")
struct BookmarkStoreTests {

    private func store() throws -> (BookmarkStore, UserDefaults) {
        let name = "bookmarks-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return (BookmarkStore(defaults: defaults), defaults)
    }

    private func mark(
        at progression: Double,
        in resource: String = "ch1.xhtml",
        chapter: String = "Chapter One",
        excerpt: String = "Text long enough that pagination has something to do with it.",
        madeAt seconds: TimeInterval = 0
    ) -> Bookmark {
        Bookmark(
            locator: #"{"href":"\#(resource)"}"#,
            resource: resource,
            progression: progression,
            chapter: chapter,
            excerpt: excerpt,
            createdAt: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test("A mark is kept, with the chapter and the excerpt the spec asks for")
    func keepsWhatTheSpecAsksFor() throws {
        let (store, _) = try store()
        store.toggle(mark(at: 0.25), in: "book")

        let kept = try #require(store.bookmarks(for: "book").first)
        #expect(kept.chapter == "Chapter One")
        #expect(kept.excerpt.hasPrefix("Text long enough"))
        #expect(kept.progression == 0.25)
    }

    @Test("Pressing the control again on the same page removes the mark")
    func togglesOffTheSamePage() throws {
        let (store, _) = try store()
        store.toggle(mark(at: 0.25), in: "book")
        store.toggle(mark(at: 0.25), in: "book")

        #expect(store.bookmarks(for: "book").isEmpty)
    }

    @Test("The same fraction in another chapter is another place")
    func doesNotConfuseResources() throws {
        let (store, _) = try store()
        store.toggle(mark(at: 0.25, in: "ch1.xhtml"), in: "book")
        store.toggle(mark(at: 0.25, in: "ch2.xhtml"), in: "book")

        #expect(store.bookmarks(for: "book").count == 2)
    }

    @Test("The list reads in book order, not in the order the marks were made")
    func ordersByPosition() throws {
        let (store, _) = try store()
        store.toggle(mark(at: 0.90, madeAt: 10), in: "book")
        store.toggle(mark(at: 0.10, madeAt: 20), in: "book")

        #expect(store.bookmarks(for: "book").map(\.progression) == [0.10, 0.90])
    }

    @Test("One publication's marks are not another's")
    func keepsPublicationsApart() throws {
        let (store, _) = try store()
        store.toggle(mark(at: 0.25), in: "one")

        #expect(store.bookmarks(for: "two").isEmpty)
    }

    @Test("Removing the last mark leaves nothing behind for that publication")
    func removesByIdentity() throws {
        let (store, _) = try store()
        let only = mark(at: 0.25)
        store.toggle(only, in: "book")
        let left = store.remove(only.id, from: "book")

        #expect(left.isEmpty)
        #expect(store.bookmarks(for: "book").isEmpty)
    }

    @Test("Marks survive being read back through a second store")
    func survivesReopening() throws {
        let (store, defaults) = try store()
        store.toggle(mark(at: 0.25), in: "book")

        #expect(BookmarkStore(defaults: defaults).bookmarks(for: "book").count == 1)
    }
}
