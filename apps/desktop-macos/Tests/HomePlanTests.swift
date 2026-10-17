import Foundation
import StoryArcCore
import Testing

@testable import StoryArc

/// Home, task 2.23c: the order of Keep reading and Up next, and the absence of an empty shelf.
@Suite("Home plan")
struct HomePlanTests {
    private func pub(_ id: String) -> Publication {
        TestPublications.named(id)
    }

    @Test("Keep reading keeps the model's order; Up next follows each finished publication")
    func order() {
        let reading = [pub("a"), pub("b")]
        let done = [pub("f1"), pub("f2")]
        let after: [String: Publication] = [done[0].id: pub("n1"), done[1].id: pub("n2")]

        let plan = HomePlan.make(
            continueReading: reading, finished: done, next: { after[$0.id] }, isUnread: { _ in true }
        )

        #expect(plan.keepReading.map(\.id) == reading.map(\.id))
        #expect(plan.upNext.map(\.id) == [after[done[0].id]?.id, after[done[1].id]?.id].compactMap { $0 })
    }

    @Test("An empty shelf is absent, and a next issue already being read is not offered twice")
    func absences() {
        let empty = HomePlan.make(continueReading: [], finished: [], next: { _ in nil }, isUnread: { _ in true })
        #expect(empty.isEmpty && empty.keepReading.isEmpty && empty.upNext.isEmpty)

        let reading = pub("n1")
        let plan = HomePlan.make(
            continueReading: [reading], finished: [pub("f1")],
            next: { _ in reading }, isUnread: { _ in true }
        )
        #expect(plan.upNext.isEmpty)
        #expect(!plan.isEmpty)
    }

    @Test("A book that cannot be opened now keeps its place in Keep reading, marked")
    func unreadableStays() {
        let reading = [pub("a"), pub("gone"), pub("b")]
        let plan = HomePlan.make(
            continueReading: reading, finished: [], next: { _ in nil }, isUnread: { _ in true },
            isReadable: { $0.id != reading[1].id }
        )
        #expect(plan.keepReading.map(\.id) == reading.map(\.id))
        #expect(plan.unreadable == [reading[1].id])
    }

    @Test("Only an unread next issue is Up next, and one is listed once")
    func unreadOnly() {
        let next = pub("n1")
        let plan = HomePlan.make(
            continueReading: [], finished: [pub("f1"), pub("f2")],
            next: { _ in next }, isUnread: { $0.id == next.id }
        )
        #expect(plan.upNext.map(\.id) == [next.id])
        let read = HomePlan.make(
            continueReading: [], finished: [pub("f1")], next: { _ in next }, isUnread: { _ in false }
        )
        #expect(read.upNext.isEmpty)
    }

    // MARK: - The rest of the surface

    private func arrived(_ id: String, daysAgo: Double) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/\(id).cbz"), format: .cbz, displayTitle: id,
            origin: .inferred, addedAt: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * 86_400)
        )
    }

    @Test("Recently added is newest first, and a shelf that holds more says so and leads to the rest")
    func recentlyAdded() {
        let library = (0..<15).map { arrived("p\($0)", daysAgo: Double($0)) }.shuffled()
        let plan = HomePlan.make(
            continueReading: [], finished: [], next: { _ in nil }, isUnread: { _ in true }, library: library
        )
        #expect(plan.recentlyAdded.map(\.displayTitle) == (0..<HomePlan.shelfLength).map { "p\($0)" })
        #expect(plan.recentlyAddedHasMore)

        let few = HomePlan.make(
            continueReading: [], finished: [], next: { _ in nil }, isUnread: { _ in true },
            library: Array(library.prefix(3))
        )
        #expect(few.recentlyAdded.count == 3)
        #expect(!few.recentlyAddedHasMore)
    }

    @Test("Finished comes grouped by the month it was finished, newest month first, and is absent when empty")
    func finishedByMonth() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let june = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 20)))
        let juneEarly = try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 2)))
        let march = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9)))
        let done: [String: Date] = ["a": june, "b": march, "c": juneEarly]
        let finished = ["a", "c", "b"].map(pub)

        let plan = HomePlan.make(
            continueReading: [], finished: finished, next: { _ in nil }, isUnread: { _ in true },
            finishedAt: { done[$0.displayTitle] }, calendar: calendar
        )
        #expect(plan.finished.map { $0.publications.map(\.displayTitle) } == [["a", "c"], ["b"]])
        #expect(plan.finished.first?.month == calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))

        let none = HomePlan.make(continueReading: [], finished: [], next: { _ in nil }, isUnread: { _ in true })
        #expect(none.finished.isEmpty && none.recentlyAdded.isEmpty && none.isEmpty)
    }
}
