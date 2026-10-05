import Testing

@testable import LibraryFeature
import StoryArcCore

/// Which publication a held search result's menu acts on.
///
/// `library-browsing`'s *A publication's actions wherever it is drawn* names search results
/// among the places — ``HeldSearchResultRow`` draws the menu only for a result this device
/// still holds, and ``heldSearchResult(for:in:)`` is the rule it asks, lifted out so a test
/// can reach it without rendering the row.
struct HeldSearchResultRowTests {
    private func publication(id: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/\(id).cbz"),
            format: .cbz,
            displayTitle: id,
            origin: .inferred
        )
    }

    @Test("A result the library still holds resolves to its publication")
    func heldResultResolves() {
        let kept = publication(id: "one")
        let other = publication(id: "two")
        #expect(heldSearchResult(for: kept.id, in: [kept, other])?.id == kept.id)
    }

    @Test("A result that has gone stale since the search resolves to nothing")
    func staleResultResolvesToNothing() {
        #expect(heldSearchResult(for: "gone", in: [publication(id: "one")]) == nil)
    }
}
