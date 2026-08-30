import Foundation
import Testing

@testable import Persistence

/// "Clear cache" removes what the Privacy screen says it removes.
///
/// The security review's rank 19: the row promises "Decoded pages and web-view
/// data" in all four languages, and the code emptied a directory. The web view's
/// *cache* is in that directory; its cookies and per-origin storage are not — so
/// an identifier a publication left behind survived the clear that was supposed
/// to have taken it, and the reader was told otherwise.
///
/// The website store is a process-wide singleton, so the real one is not called
/// here: what is asserted is that clearing asks for it. Android's
/// `ClearCacheTest` asserts the same two things in the same order.
@Suite("Clear cache")
struct ClearCacheTests {

    /// A box a `@Sendable` closure can tick, since the closure cannot capture `var`.
    private final class Spy: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        func record() {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }

    private func makeCaches() throws -> URL {
        let caches = URL.temporaryDirectory
            .appending(path: "clear-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        try Data("a decoded page".utf8).write(to: caches.appending(path: "page.bin"))
        return caches
    }

    @Test("Clearing empties the caches directory, as it always did")
    func clearingEmptiesTheDirectory() async throws {
        let caches = try makeCaches()
        defer { try? FileManager.default.removeItem(at: caches) }
        let usage = StorageUsage(caches: caches, removeWebsiteData: {})

        #expect(usage.cacheBytes() > 0)
        await usage.clearCache()
        #expect(usage.cacheBytes() == 0)
    }

    @Test("Clearing also asks the web view for its cookies and origin storage")
    func clearingAlsoClearsTheWebView() async throws {
        let caches = try makeCaches()
        defer { try? FileManager.default.removeItem(at: caches) }
        let spy = Spy()
        let usage = StorageUsage(caches: caches, removeWebsiteData: { spy.record() })

        await usage.clearCache()

        #expect(spy.callCount == 1)
    }
}
