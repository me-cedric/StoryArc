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
}
