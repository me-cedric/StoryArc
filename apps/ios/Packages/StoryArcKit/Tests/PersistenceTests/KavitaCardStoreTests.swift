import Foundation
import Testing

@testable import Persistence
@testable import StoryArcCore

/// What a Kavita server said, kept so a download can be read without it.
///
/// Android's `KavitaCardStoreTest` makes the same five claims in the same order.
struct KavitaCardStoreTests {
    private func store() throws -> KavitaCardStore {
        let defaults = try #require(UserDefaults(suiteName: "cards-\(UUID().uuidString)"))
        return KavitaCardStore(defaults: defaults)
    }

    /// The store's own key, restated so a rename has to be deliberate.
    private let key = "app.storyarc.kavita.cards"

    @Test("A card written by an older build still reads")
    func olderCardStillReads() throws {
        // Not a `KavitaCard` re-encoded: the actual bytes an older build left in the
        // defaults, with none of the keys the fields added since carry. Swift's derived
        // decoder throws `keyNotFound` for an absent key rather than taking the property's
        // default, and the store decodes every card as one dictionary — so one undecodable
        // card does not lose two fields, it loses the reader's whole offline library.
        let defaults = try #require(UserDefaults(suiteName: "cards-\(UUID().uuidString)"))
        let legacy = """
        {"p1":{"publicationId":"p1","sourceId":"s","seriesId":7,"chapterId":1,\
        "seriesName":"Tidal Reach","chapterName":"The Harbour",\
        "people":["Ada Okonkwo"],"subjects":["Adventure"],"releaseYear":1998}}
        """
        defaults.set(Data(legacy.utf8), forKey: key)

        let store = KavitaCardStore(defaults: defaults)
        let read = try #require(store.card(of: "p1"))
        #expect(read.seriesName == "Tidal Reach")
        #expect(read.facts == ["1998", "Ada Okonkwo", "Adventure"])
        // The fields that row never had, at the defaults the memberwise initialiser gives.
        #expect(read.downloadId == "")
        #expect(read.libraryId == 0)
    }

    private func card(
        _ publication: String,
        source: String = "s",
        series: String = "Tidal Reach",
        chapter: Int = 1
    ) -> KavitaCard {
        KavitaCard(
            publicationId: publication,
            downloadId: "download-\(publication)",
            sourceId: source,
            libraryId: 3,
            seriesId: 7,
            chapterId: chapter,
            seriesName: series,
            chapterName: "The Harbour",
            summary: "A summary the server holds.",
            people: ["Ada Okonkwo"],
            subjects: ["Adventure"],
            releaseYear: 1998
        )
    }

    @Test("A card survives a round trip whole")
    func roundTrip() throws {
        let store = try store()
        store.save(card("p1"))
        let read = try #require(store.card(of: "p1"))
        #expect(read.summary == "A summary the server holds.")
        // The whole chain, because a progress post missing one of the four is refused.
        #expect(read.libraryId == 3)
        #expect(read.downloadId == "download-p1")
        #expect(read.facts == ["1998", "Ada Okonkwo", "Adventure"])
    }

    @Test("A second keep of the same publication replaces the first")
    func replaced() throws {
        let store = try store()
        store.save(card("p1", series: "Old name"))
        store.save(card("p1", series: "Tidal Reach"))
        #expect(store.all().count == 1)
        #expect(store.card(of: "p1")?.seriesName == "Tidal Reach")
    }

    @Test("Cards are narrowed to one source")
    func perSource() throws {
        let store = try store()
        store.save(card("p1", source: "a"))
        store.save(card("p2", source: "b"))
        #expect(store.all(from: "a").map(\.publicationId) == ["p1"])
    }

    @Test("Removing a publication's card leaves the others")
    func removeOne() throws {
        let store = try store()
        store.save(card("p1"))
        store.save(card("p2"))
        store.remove("p1")
        #expect(store.all().map(\.publicationId) == ["p2"])
    }

    @Test("Removing a source takes every card it produced")
    func removeSource() throws {
        // `sources` makes removing a source take its downloads with it, and what was cached
        // about them is part of what it took.
        let store = try store()
        store.save(card("p1", source: "a"))
        store.save(card("p2", source: "a"))
        store.save(card("p3", source: "b"))
        store.removeAll(from: "a")
        #expect(store.all().map(\.publicationId) == ["p3"])
    }
}
