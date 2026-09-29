import Foundation
import Testing

@testable import Persistence

/// What the reader chose on the end screen about a finished download (D7). Android's
/// `CleanupChoicesTest` asserts the same table.
@Suite("Cleanup choices")
struct CleanupChoicesTests {
    private struct Suite {
        let store: CleanupChoices
        let defaults: UserDefaults
        let name: String

        func discard() { defaults.removePersistentDomain(forName: name) }
    }

    private func fresh() throws -> Suite {
        let name = "test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return Suite(store: CleanupChoices(defaults: defaults), defaults: defaults, name: name)
    }

    @Test("Nothing kept yet holds nothing")
    func nothingKeptYet() throws {
        let suite = try fresh()
        defer { suite.discard() }
        #expect(!suite.store.isKept("one"))
    }

    @Test("A kept download is kept, and no other download is")
    func keepsOnlyThatOne() throws {
        let suite = try fresh()
        defer { suite.discard() }
        suite.store.keep("one")
        #expect(suite.store.isKept("one"))
        #expect(!suite.store.isKept("two"))
    }

    @Test("A kept download survives a fresh store over the same suite")
    func survivesTheRoundTrip() throws {
        let suite = try fresh()
        defer { suite.discard() }
        suite.store.keep("one")
        #expect(CleanupChoices(defaults: suite.defaults).isKept("one"))
    }

    @Test("With the sweep on, a download goes on close unless the reader kept it")
    func sweepOnRemovesUnlessKept() throws {
        let suite = try fresh()
        defer { suite.discard() }
        #expect(suite.store.isRemovedOnClose("one", automaticCleanupIsOn: true))
        suite.store.keep("one")
        #expect(!suite.store.isRemovedOnClose("one", automaticCleanupIsOn: true))
    }

    @Test("With the sweep off, a download goes on close only when the reader asked")
    func sweepOffRemovesOnlyWhenAsked() throws {
        let suite = try fresh()
        defer { suite.discard() }
        #expect(!suite.store.isRemovedOnClose("one", automaticCleanupIsOn: false))
        suite.store.removeOnClose("one")
        #expect(suite.store.isRemovedOnClose("one", automaticCleanupIsOn: false))
        #expect(!suite.store.isRemovedOnClose("two", automaticCleanupIsOn: false))
    }

    @Test("Keep withdraws a removal the reader asked for")
    func keepWithdrawsARemoval() throws {
        let suite = try fresh()
        defer { suite.discard() }
        suite.store.removeOnClose("one")
        suite.store.keep("one")
        #expect(!suite.store.isRemovedOnClose("one", automaticCleanupIsOn: false))
        #expect(suite.store.takeRemovals().isEmpty)
    }

    @Test("A removal the reader asked for is handed over once, then forgotten")
    func removalsAreTakenOnce() throws {
        let suite = try fresh()
        defer { suite.discard() }
        suite.store.removeOnClose("one")
        #expect(suite.store.takeRemovals() == ["one"])
        #expect(suite.store.takeRemovals().isEmpty)
        #expect(!suite.store.isRemovedOnClose("one", automaticCleanupIsOn: false))
    }
}
