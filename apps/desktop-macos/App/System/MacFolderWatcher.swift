import CoreServices
import Foundation

/// Turns a burst of change events into a few reconciles.
///
/// `desktop-experience`, *A burst of changes*: thousands of files change at once and the
/// library updates in batches with the window responsive. Events are counted and the
/// reconcile is asked for once per quiet period, so a 2,000-file copy is a handful of
/// walks rather than two thousand. Pure, so `FolderWatcherTests` can hold the arithmetic.
struct EventBatcher: Sendable, Equatable {
    /// How long a burst has to pause before the batch is handed on.
    static let quietPeriod: Duration = .seconds(1)

    private(set) var pendingEvents = 0
    private(set) var batches = 0

    mutating func noteEvents(_ count: Int) {
        pendingEvents += count
    }

    /// Closes the batch at the end of a quiet period. True when there was anything in it.
    mutating func closeBatch() -> Bool {
        guard pendingEvents > 0 else { return false }
        pendingEvents = 0
        batches += 1
        return true
    }
}

/// FSEvents over the chosen folders, batched, calling back on the main actor.
///
/// FSEvents rather than a descriptor per directory: `LibraryFeature`'s `FolderWatcher`
/// opens one vnode source per directory up to a ceiling of 96, which is right on a phone
/// and wrong for a Mac library of a thousand series. One stream covers a whole tree, and
/// its own latency coalesces the first second of a burst before ``EventBatcher`` does
/// the rest. Task 2.20.
@MainActor
final class MacFolderWatcher {
    private var stream: FSEventStreamRef?
    private var batcher = EventBatcher()
    private var quiet: Task<Void, Never>?
    private var onBatch: (@MainActor () async -> Void)?
    private(set) var batchesDelivered = 0

    isolated deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// Watches these folders and everything under them, replacing the previous watch.
    func watch(_ folders: [URL], onBatch: @escaping @MainActor () async -> Void) {
        stop()
        self.onBatch = onBatch
        guard !folders.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let paths = folders.map { $0.path(percentEncoded: false) } as CFArray
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            nil, Self.callback, &context, paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(created, .main)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        quiet?.cancel()
        quiet = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        batcher = EventBatcher()
    }

    private static let callback: FSEventStreamCallback = { _, info, count, _, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<MacFolderWatcher>.fromOpaque(info).takeUnretainedValue()
        // The stream's queue is the main queue, so this is already where the watcher lives.
        MainActor.assumeIsolated { watcher.noteEvents(count) }
    }

    private func noteEvents(_ count: Int) {
        batcher.noteEvents(count)
        quiet?.cancel()
        quiet = Task { [weak self] in
            try? await Task.sleep(for: EventBatcher.quietPeriod)
            guard !Task.isCancelled else { return }
            await self?.deliver()
        }
    }

    private func deliver() async {
        guard batcher.closeBatch() else { return }
        batchesDelivered += 1
        await onBatch?()
    }
}
