import Foundation
import Persistence
import StoryArcCore

/// Where a position goes. `ProgressStore` in the app, a spy in a test.
protocol ProgressWriting: Sendable {
    func save(_ progress: ReadingProgress) async throws
}

extension ProgressStore: ProgressWriting {}

/// Writes a reader window's position: on a cadence while reading, before the window
/// closes, before the app quits, and again at the next launch when a write failed.
///
/// `desktop-experience`, *Closing a window and quitting the app*. A turn is noted at once
/// and written no later than `delay` after the last one, never once per frame; `flush()`
/// writes what is pending and is what a close and a quit call. A failed write keeps the
/// position in memory and in `pendingKey` under `UserDefaults`, so the next launch retries
/// it through ``retryPending(into:defaults:)``, and the failure is named in
/// ``lastFailure`` for the diagnostic. Task 2.17.
@MainActor
@Observable
final class ProgressWriter {
    static let pendingKey = "app.storyarc.mac.pendingProgress"

    private let store: any ProgressWriting
    private let delay: Duration
    private let defaults: UserDefaults
    private var pending: ReadingProgress?
    private var scheduled: Task<Void, Never>?

    /// The last write that did not happen, as a sentence for the diagnostic.
    private(set) var lastFailure: String?
    private(set) var writes = 0

    init(store: any ProgressWriting, delay: Duration = .seconds(5), defaults: UserDefaults = .standard) {
        self.store = store
        self.delay = delay
        self.defaults = defaults
    }

    /// What is waiting to be written, if anything.
    var isPending: Bool { pending != nil }

    /// A position reached. Written after `delay` unless another arrives first.
    func note(_ progress: ReadingProgress) {
        pending = progress
        scheduled?.cancel()
        scheduled = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    /// Writes what is pending now. True when nothing is left owed.
    @discardableResult
    func flush() async -> Bool {
        scheduled?.cancel()
        scheduled = nil
        guard let progress = pending else { return true }
        do {
            try await store.save(progress)
            writes += 1
            pending = nil
            lastFailure = nil
            Self.clearPending(for: progress.identity, defaults: defaults)
            return true
        } catch {
            // Kept, in memory and on disk, and the window still closes: the spec says the
            // app retries at the next launch and names the failure in the diagnostic.
            lastFailure = "\(progress.identity.stableID): \(error)"
            Self.keepPending(progress, defaults: defaults)
            // A full disk is named in the preferences and the Downloads view (task 3.15).
            MacLibrary.live?.storage.noteWriteFailure(error)
            return false
        }
    }

    // MARK: - The retry at the next launch

    private static func keepPending(_ progress: ReadingProgress, defaults: UserDefaults) {
        var all = pendingRecords(defaults: defaults).filter { !$0.identity.matches(progress.identity) }
        all.append(progress)
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: pendingKey) }
    }

    private static func clearPending(for identity: PublicationIdentity, defaults: UserDefaults) {
        let rest = pendingRecords(defaults: defaults).filter { !$0.identity.matches(identity) }
        if rest.isEmpty {
            defaults.removeObject(forKey: pendingKey)
        } else if let data = try? JSONEncoder().encode(rest) {
            defaults.set(data, forKey: pendingKey)
        }
    }

    static func pendingRecords(defaults: UserDefaults = .standard) -> [ReadingProgress] {
        guard let data = defaults.data(forKey: pendingKey),
              let records = try? JSONDecoder().decode([ReadingProgress].self, from: data)
        else { return [] }
        return records
    }

    /// Writes every position a failed write left behind. Records that fail again stay.
    @discardableResult
    static func retryPending(into store: any ProgressWriting, defaults: UserDefaults = .standard) async -> Int {
        var written = 0
        for record in pendingRecords(defaults: defaults) {
            guard (try? await store.save(record)) != nil else { continue }
            clearPending(for: record.identity, defaults: defaults)
            written += 1
        }
        return written
    }
}
