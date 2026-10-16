import Foundation
import StoryArcCore
import Testing

@testable import StoryArc

/// What the spy store throws while it refuses.
private struct Refused: Error {}

/// The write cadence of task 2.17, against a store that can be told to fail.
@MainActor
@Suite("Progress writer")
struct ProgressWriterTests {
    /// Counts saves, and refuses them while told to.
    private final class SpyStore: ProgressWriting, @unchecked Sendable {
        var saved: [ReadingProgress] = []
        var refuses = false

        func save(_ progress: ReadingProgress) async throws {
            if refuses { throw Refused() }
            saved.append(progress)
        }
    }

    private func record(_ page: Int, id: String = "saga") -> ReadingProgress {
        ReadingProgress(
            identity: PublicationIdentity(normalizedPath: "/comics/\(id).cbz"),
            position: .page(index: page, of: 24),
            updatedAt: Date()
        )
    }

    private func defaults() throws -> (UserDefaults, String) {
        let name = "mac-progress-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test("Turns are written once after the delay, never once per turn")
    func writesAfterTheDelay() async throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SpyStore()
        let writer = ProgressWriter(store: store, delay: .milliseconds(100), defaults: defaults)

        for page in 1...5 { writer.note(record(page)) }
        #expect(store.saved.isEmpty)
        #expect(writer.isPending)

        try await Task.sleep(for: .milliseconds(400))
        #expect(store.saved.map(\.position) == [.page(index: 5, of: 24)])
        #expect(!writer.isPending)
    }

    @Test("Closing a window writes the position before the delay runs out")
    func flushWritesAtOnce() async throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SpyStore()
        let writer = ProgressWriter(store: store, delay: .seconds(60), defaults: defaults)
        writer.note(record(7))

        let done = await writer.flush()

        #expect(done)
        #expect(store.saved.map(\.position) == [.page(index: 7, of: 24)])
        #expect(await writer.flush())
        #expect(store.saved.count == 1)
    }

    @Test("A write that fails still lets the window close, keeps the position, and retries at the next launch")
    func failedWriteIsRetried() async throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SpyStore()
        store.refuses = true
        let writer = ProgressWriter(store: store, delay: .seconds(60), defaults: defaults)
        writer.note(record(9))

        let done = await writer.flush()

        #expect(!done)
        #expect(writer.isPending)
        #expect(writer.lastFailure?.contains("Refused") == true)
        #expect(ProgressWriter.pendingRecords(defaults: defaults).map(\.position) == [.page(index: 9, of: 24)])

        // The next launch, with the disk back.
        store.refuses = false
        let written = await ProgressWriter.retryPending(into: store, defaults: defaults)
        #expect(written == 1)
        #expect(store.saved.map(\.position) == [.page(index: 9, of: 24)])
        #expect(ProgressWriter.pendingRecords(defaults: defaults).isEmpty)
    }

    @Test("A pending record is replaced by a later write of the same publication, and others stay")
    func pendingIsPerPublication() async throws {
        let (defaults, name) = try defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SpyStore()
        store.refuses = true
        let saga = ProgressWriter(store: store, delay: .seconds(60), defaults: defaults)
        let monstress = ProgressWriter(store: store, delay: .seconds(60), defaults: defaults)
        saga.note(record(2))
        await saga.flush()
        monstress.note(record(3, id: "monstress"))
        await monstress.flush()
        saga.note(record(4))
        await saga.flush()

        let pending = ProgressWriter.pendingRecords(defaults: defaults)
        #expect(pending.count == 2)
        #expect(pending.first { $0.identity.normalizedPath == "/comics/saga.cbz" }?.position == .page(index: 4, of: 24))
    }
}
