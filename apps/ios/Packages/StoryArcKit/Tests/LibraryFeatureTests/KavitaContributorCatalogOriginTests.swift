import Foundation
import Kavita
@testable import LibraryFeature
import Persistence
import StoryArcCore
import Testing

/// A library-held Kavita row's own address on the server, caught at the moment a browse
/// reads it rather than only when a reader opens or keeps it.
///
/// `kavita-server` task 12.1: joining a server reading list from a row the library lists —
/// never opened, never kept — needs ``KavitaOrigin`` to exist for it, and until this it did
/// not: only ``KavitaChapterList`` and ``KavitaKeep`` wrote one. This proves
/// ``KavitaContributor/catalogOrigins(source:series:volume:)``, the rule
/// ``KavitaContributor/page(source:client:page:store:)`` calls for every volume it reads,
/// and proves the two stores stay apart: a catalogued origin never answers
/// ``KavitaProgressStore/publication(forChapter:)``, which means "this device has opened
/// it" and must keep meaning only that.
@Suite("A browsed chapter's catalogued origin")
struct KavitaContributorCatalogOriginTests {

    private let source = UUID()
    private let series = KavitaSeries(id: 312, name: "Lantern Green", libraryId: 7)
    private let volume = KavitaVolume(
        id: 55,
        number: 1,
        chapters: [
            KavitaChapter(id: 3103, number: "43", pages: 22),
            KavitaChapter(id: 3104, number: "44", pages: 18),
        ]
    )

    /// A store backed by its own defaults suite, so parallel tests never share one file.
    private func store() throws -> KavitaProgressStore {
        KavitaProgressStore(defaults: try #require(UserDefaults(suiteName: UUID().uuidString)))
    }

    private func publicationId(_ chapterId: Int) -> String {
        KavitaContributor.publication(
            source: source,
            series: series,
            chapter: volume.chapters.first { $0.id == chapterId }!
        ).id
    }

    @Test("Every chapter in the volume gets its own origin, keyed by its row")
    func onePerChapter() {
        let origins = KavitaContributor.catalogOrigins(source: source, series: series, volume: volume)

        #expect(origins.count == 2)
        let first = origins[publicationId(3103)]
        #expect(first?.sourceId == source.uuidString)
        #expect(first?.libraryId == 7)
        #expect(first?.seriesId == 312)
        #expect(first?.volumeId == 55)
        #expect(first?.chapterId == 3103)
        #expect(first?.pages == 22)
    }

    @Test("A catalogued origin resolves, but is not mistaken for an opened one")
    func resolvesWithoutClaimingAnOpen() throws {
        let store = try store()
        store.rememberCatalog(KavitaContributor.catalogOrigins(source: source, series: series, volume: volume))

        let id = publicationId(3103)
        #expect(store.origin(of: id) == nil)
        #expect(store.catalogOrigin(of: id)?.chapterId == 3103)
        #expect(store.resolvedOrigin(of: id)?.chapterId == 3103)
        // `publication(forChapter:)` answers "has this device opened it" — a catalogued
        // origin must never make that true.
        #expect(store.publication(forChapter: 3103) == nil)
    }

    @Test("An opened origin outranks a catalogued one")
    func openedOutranksCatalogued() throws {
        let store = try store()
        let id = publicationId(3103)
        // The catalogued note (from `catalogOrigins` above) carries `pages: 22`. The opened
        // note below deliberately disagrees — `pages: 99` — so the two are distinguishable:
        // a resolver that picked the wrong one would still answer *a* value, and only a
        // mismatched field proves which one it picked.
        store.rememberCatalog(KavitaContributor.catalogOrigins(source: source, series: series, volume: volume))
        let opened = KavitaOrigin(
            sourceId: source.uuidString, libraryId: 7, seriesId: 312, volumeId: 55, chapterId: 3103, pages: 99
        )
        store.remember(opened, for: id)

        #expect(store.resolvedOrigin(of: id)?.pages == 99)
        #expect(store.publication(forChapter: 3103) == id)
    }
}
