public import Foundation

/// Every download the app knows about, and every change that can be made to the set.
///
/// A value type with pure operations, like ``SourceRegistry``. The queue's *order* is the
/// reader's — `offline-downloads` asks for "per-item and global pause, resume, cancel, and
/// reorder" — so this is an array, not a dictionary keyed by identity.
public struct DownloadLibrary: Sendable, Equatable {
    public private(set) var downloads: [Download]

    public init(downloads: [Download] = []) {
        self.downloads = downloads
    }

    public subscript(id: Download.ID) -> Download? {
        downloads.first { $0.id == id }
    }

    /// The ones still to do, in the order they will be done.
    public var pending: [Download] { downloads.filter { !$0.state.isFinished } }

    /// The ones on disk.
    public var finished: [Download] { downloads.filter(\.state.isFinished) }

    /// What all the finished downloads weigh, for the storage view.
    public var bytesOnDisk: Int64 { finished.reduce(0) { $0 + $1.downloadedBytes } }

    /// Queues a download, or does nothing if this publication is already known.
    ///
    /// `offline-downloads`: when a publication is already downloaded "the app does not
    /// re-fetch it". Enforced here rather than at the call site, because there are three
    /// call sites and only one of them would remember.
    public func queueing(_ download: Download) -> DownloadLibrary {
        guard self[download.id] == nil else { return self }
        return DownloadLibrary(downloads: downloads + [download])
    }

    /// Records a change of state.
    public func marking(_ id: Download.ID, as state: Download.State) -> DownloadLibrary {
        DownloadLibrary(downloads: downloads.map { each in
            guard each.id == id else { return each }
            var changed = each
            changed.state = state
            if state == .finished { changed.completedAt = Date() }
            return changed
        })
    }

    /// Records progress, and the total once the server has stated it.
    public func advancing(
        _ id: Download.ID,
        downloaded: Int64,
        expected: Int64? = nil
    ) -> DownloadLibrary {
        DownloadLibrary(downloads: downloads.map { each in
            guard each.id == id else { return each }
            var changed = each
            changed.downloadedBytes = downloaded
            if let expected { changed.expectedBytes = expected }
            return changed
        })
    }

    /// Moves a download in the queue.
    ///
    /// Takes the destination a drag reports, which is an index in the list *before* the
    /// move — the same convention ``SourceRegistry/moving(_:to:)`` uses, and for the same
    /// reason: removing first and inserting after lands one place early on every downward
    /// drag.
    public func moving(_ id: Download.ID, to destination: Int) -> DownloadLibrary {
        guard let from = downloads.firstIndex(where: { $0.id == id }) else { return self }
        var moved = downloads
        let download = moved.remove(at: from)
        let to = min(max(destination > from ? destination - 1 : destination, 0), moved.count)
        moved.insert(download, at: to)
        return DownloadLibrary(downloads: moved)
    }

    /// Forgets a download. The file is the caller's to delete.
    public func removing(_ id: Download.ID) -> DownloadLibrary {
        DownloadLibrary(downloads: downloads.filter { $0.id != id })
    }

    /// Forgets everything a source contributed, for when the source itself is removed.
    public func removingAll(from sourceID: UUID) -> (library: DownloadLibrary, removed: [Download]) {
        let removed = downloads.filter { $0.sourceID == sourceID }
        let kept = downloads.filter { $0.sourceID != sourceID }
        return (DownloadLibrary(downloads: kept), removed)
    }

    /// Records a failed attempt, counting it.
    ///
    /// Always leaves the download `.failed`. Whether to try again is ``shouldRetry(_:)``'s
    /// question, asked by the queue — a state that re-queued itself would make "failed"
    /// mean two different things and leave nothing for the reader to see between attempts.
    ///
    /// `offline-downloads`: a failure "is retried automatically up to three times with
    /// backoff, then marked failed with a plain-language reason". The count lives in the
    /// state so it survives an app restart rather than resetting to zero.
    public func failing(_ id: Download.ID, reason: String) -> DownloadLibrary {
        DownloadLibrary(downloads: downloads.map { each in
            guard each.id == id else { return each }
            let previous = if case let .failed(_, attempts) = each.state { attempts } else { 0 }
            var changed = each
            changed.state = .failed(reason: reason, attempts: previous + 1)
            return changed
        })
    }

    /// Whether a failed download has attempts left.
    public static func shouldRetry(_ download: Download) -> Bool {
        guard case let .failed(_, attempts) = download.state else { return false }
        return attempts < attemptLimit
    }

    /// How long to wait before the next attempt.
    ///
    /// Doubling from two seconds, which is the "backoff" the spec asks for. Short, because
    /// the common failure is a server that was briefly busy or a phone that changed
    /// network, not one that will be down for an hour.
    public static func backoff(afterAttempts attempts: Int) -> Duration {
        .seconds(2 << max(0, attempts - 1))
    }

    /// Three, from `offline-downloads`.
    public static let attemptLimit = 3
}
