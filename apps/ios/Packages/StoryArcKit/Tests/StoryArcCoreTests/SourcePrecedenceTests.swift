import Foundation
import Testing

@testable import StoryArcCore

/// Which of two sources holding one publication wins.
///
/// `sources` says the reader's order decides it. The order persisted and nothing read it, so
/// every case here is the `Reordering sources` scenario's second clause. Android's
/// `SourcePrecedenceTest` asserts the same table in the same order.
@Suite("Source precedence")
struct SourcePrecedenceTests {

    private let first = Source(displayName: "Kavita", kind: .kavitaServer)
    private let second = Source(displayName: "Comics", kind: .localFolder)

    private var registry: [Source] { [first, second] }

    @Test("The source the reader put higher wins the title")
    func higherSourceWins() {
        #expect(SourcePrecedence.prefers(first.id, over: second.id, in: registry))
    }

    @Test("A lower source does not take a title off a higher one")
    func lowerSourceDoesNotDisplace() {
        #expect(!SourcePrecedence.prefers(second.id, over: first.id, in: registry))
    }

    @Test("A second find through the same source changes nothing")
    func sameSourceDoesNotDisplaceItself() {
        #expect(!SourcePrecedence.prefers(first.id, over: first.id, in: registry))
    }

    @Test("A publication that came through a source beats one that came through none")
    func attributedBeatsUnattributed() {
        // A file in the app's own folder is not a library the reader configured.
        #expect(SourcePrecedence.prefers(second.id, over: nil, in: registry))
        #expect(!SourcePrecedence.prefers(nil, over: second.id, in: registry))
    }

    @Test("A source the registry no longer holds ranks with the unattributed")
    func removedSourceRanksLast() {
        let removed = UUID()

        #expect(SourcePrecedence.rank(of: removed, in: registry) == Int.max)
        #expect(SourcePrecedence.rank(of: nil, in: registry) == Int.max)
        #expect(!SourcePrecedence.prefers(removed, over: second.id, in: registry))
    }

    @Test("Rank is the position in the registry, which is what a drag changes")
    func rankFollowsTheOrder() {
        #expect(SourcePrecedence.rank(of: first.id, in: registry) == 0)
        #expect(SourcePrecedence.rank(of: second.id, in: registry) == 1)

        // The same two sources, dragged the other way round.
        let dragged = [second, first]
        #expect(SourcePrecedence.rank(of: first.id, in: dragged) == 1)
        #expect(SourcePrecedence.prefers(second.id, over: first.id, in: dragged))
    }
}
