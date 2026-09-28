import Foundation
import Testing

@testable import Persistence

/// Downloads exempted from the automatic sweep (D7's "Keep" action).
@Suite("Kept from cleanup")
struct KeptFromCleanupTests {
    private struct Suite {
        let store: KeptFromCleanup
        let defaults: UserDefaults
        let name: String

        func discard() { defaults.removePersistentDomain(forName: name) }
    }

    private func fresh() throws -> Suite {
        let name = "test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return Suite(store: KeptFromCleanup(defaults: defaults), defaults: defaults, name: name)
    }

    @Test("Nothing kept yet holds nothing")
    func nothingKeptYet() throws {
        let suite = try fresh()
        defer { suite.discard() }
        #expect(!suite.store.contains("one"))
    }

    @Test("A kept download is kept, and no other download is")
    func keepsOnlyThatOne() throws {
        let suite = try fresh()
        defer { suite.discard() }
        suite.store.keep("one")
        #expect(suite.store.contains("one"))
        #expect(!suite.store.contains("two"))
    }

    @Test("Keeping the same download twice changes nothing")
    func keepingTwiceIsIdempotent() throws {
        let suite = try fresh()
        defer { suite.discard() }
        suite.store.keep("one")
        suite.store.keep("one")
        #expect(suite.store.contains("one"))
    }

    @Test("A kept download survives a fresh store over the same suite")
    func survivesTheRoundTrip() throws {
        let suite = try fresh()
        defer { suite.discard() }
        suite.store.keep("one")
        #expect(KeptFromCleanup(defaults: suite.defaults).contains("one"))
    }
}
