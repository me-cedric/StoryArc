import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// `collections-and-reading-lists` task 7.1: a reading list's next/previous flow must walk
/// forward (or back) past entries whose publication is gone, and only then try the next list
/// or fall back to the series. ``LibraryModel/next(after:)`` and
/// ``LibraryModel/previous(before:)`` used to give up on the first unavailable id and jump
/// straight to the series fallback. Android's `NextEntrySkipsUnavailableTest` makes the same
/// claim against `LibraryViewModel`.
@Suite("Next entry skips an unavailable one")
@MainActor
struct NextEntrySkipsUnavailableTests {

    private static let server = UUID()

    private func publication(_ title: String, remoteID: String) -> Publication {
        Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: Self.server, remoteID: remoteID),
                normalizedPath: nil
            ),
            format: .cbz,
            displayTitle: title,
            origin: .authoritative
        )
    }

    @Test("next() walks past a gone entry to the next available one in the same list")
    func nextSkipsGoneEntries() {
        let first = publication("A", remoteID: "a")
        let second = publication("B", remoteID: "b")
        let third = publication("C", remoteID: "c")

        let model = LibraryModel()
        model.publications = [first, second, third]
        model.shelves = Shelves(lists: [
            ReadingList(
                name: "Crossover",
                entries: [first.id, "gone-1", second.id, "gone-2", third.id]
            )
        ])

        #expect(model.next(after: first)?.id == second.id)
        #expect(model.next(after: second)?.id == third.id)
    }

    @Test("previous() walks back past a gone entry to the prior available one")
    func previousSkipsGoneEntries() {
        let first = publication("A", remoteID: "a")
        let second = publication("B", remoteID: "b")
        let third = publication("C", remoteID: "c")

        let model = LibraryModel()
        model.publications = [first, second, third]
        model.shelves = Shelves(lists: [
            ReadingList(
                name: "Crossover",
                entries: [first.id, "gone-1", second.id, "gone-2", third.id]
            )
        ])

        #expect(model.previous(before: third)?.id == second.id)
        #expect(model.previous(before: second)?.id == first.id)
    }
}
