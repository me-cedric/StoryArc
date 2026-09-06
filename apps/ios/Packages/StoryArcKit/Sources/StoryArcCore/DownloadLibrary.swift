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
    /// Puts back every running download that nothing is actually carrying.
    ///
    /// `carried` is what is genuinely in flight — the platform's own list of transfers,
    /// plus whatever this process started. A download outside it is waiting for a
    /// completion that will never arrive, and it holds a concurrency slot while it waits.
    public func reclaiming(carriedBy carried: Set<Download.ID>) -> DownloadLibrary {
        downloads
            .filter { $0.state == .running && !carried.contains($0.id) }
            .reduce(self) { $0.marking($1.id, as: .queued) }
    }

    /// Holds everything still to do, because the device is out of room.
    ///
    /// `offline-downloads`' *Device storage is low*: "the app pauses downloads". Pauses,
    /// with the reason on every row — not a queue that quietly stops, which is what a
    /// global hold on its own looks like from the downloads screen.
    ///
    /// Only the queued and the running. A finished download has nothing to pause, and a
    /// download the reader paused is left exactly as they left it: overwriting
    /// ``Download/Pause/byReader`` here would resume it the moment space returned, which is
    /// not what they asked for.
    public func pausingForSpace() -> DownloadLibrary {
        downloads
            .filter { $0.state == .queued || $0.state == .running }
            .reduce(self) { $0.marking($1.id, as: .paused(.outOfSpace)) }
    }

    /// Puts back everything that was only waiting for room.
    ///
    /// The exact inverse of ``pausingForSpace()``, and deliberately narrower than "resume
    /// everything": a download the reader paused stays paused, and a failed one stays
    /// failed with its reason and its count. Space returning answers one question, and this
    /// un-asks only that one.
    public func resumingAfterSpace() -> DownloadLibrary {
        downloads
            .filter { $0.state == .paused(.outOfSpace) }
            .reduce(self) { $0.marking($1.id, as: .queued) }
    }

    /// Holds every unfinished download the connection no longer permits, and puts back every
    /// one it now does.
    ///
    /// `offline-downloads`' *Wi-Fi only*: with the setting on and the device on cellular,
    /// downloads "pause and state that they are waiting for Wi-Fi, and resume automatically
    /// when it returns". The queue used to answer only the first half at the moment a
    /// transfer *started*, so a reader who began a download on Wi-Fi and walked out of range
    /// kept downloading over cellular — the setting protected the queue and not the transfer
    /// already running.
    ///
    /// The mirror of ``pausingForSpace()`` and ``resumingAfterSpace()``, with one difference
    /// that earns itself: both directions are decided in **one pass**. A connection that
    /// drops and returns repeatedly would otherwise pause and resume the same row twice per
    /// pass, and every one of those is a write to the store.
    ///
    /// - Parameter permits: whether this download may move bytes over the connection the
    ///   device is on. ``MeteredDownload/mayStart(wifiOnly:isMetered:isOverridden:)`` is the
    ///   rule, asked here so a granted publication is never paused by a hold meant for the
    ///   rest of the queue.
    ///
    /// A download the reader paused, a failed one and a finished one are left exactly as they
    /// are, for ``pausingForSpace()``'s reason: this answers one question and un-asks only
    /// that one.
    public func reconsideringWifi(permits: (Download) -> Bool) -> DownloadLibrary {
        downloads.reduce(self) { library, download in
            switch download.state {
            case .queued, .running:
                permits(download)
                    ? library
                    : library.marking(download.id, as: .paused(.waitingForWiFi))
            case .paused(.waitingForWiFi):
                permits(download) ? library.marking(download.id, as: .queued) : library
            default:
                library
            }
        }
    }

    /// Whether the reader's own maximum download size is reached.
    ///
    /// `offline-downloads`' *Storage limit*: "the app stops downloading when the limit is
    /// reached". A queue with nothing left to do is not at the limit, because there is
    /// nothing for the limit to stop.
    public func isAtLimit(_ limit: Int64?) -> Bool {
        guard let limit, !pending.isEmpty else { return false }
        return bytesOnDisk >= limit
    }

    /// What the queue is waiting for, in the reader's terms, or `nil` when it is not waiting.
    ///
    /// `offline-downloads` requires a held queue to *say* what it is waiting for, because the
    /// three situations have three different remedies. Read from the records the queue wrote
    /// rather than from the connection, which is what lets a settings screen answer without
    /// holding a queue at all — and what makes the answer survive a relaunch.
    ///
    /// The device's own shortage is named first. The other two are conditions the reader
    /// chose and can unchoose; this one is a fact about the phone, and it has to be said out
    /// loud before either of the others is worth mentioning.
    ///
    /// A download the reader paused is not a hold. They stopped it, they know why, and the
    /// row itself offers the remedy.
    public func hold(limit: Int64?) -> DownloadHold? {
        if pending.contains(where: { $0.state == .paused(.outOfSpace) }) { return .outOfSpace }
        if pending.contains(where: { $0.state == .paused(.waitingForWiFi) }) {
            return .waitingForWifi
        }
        return isAtLimit(limit) ? .storageFull : nil
    }

    public func moving(_ id: Download.ID, to destination: Int) -> DownloadLibrary {
        guard let from = downloads.firstIndex(where: { $0.id == id }) else { return self }
        var moved = downloads
        let download = moved.remove(at: from)
        let to = min(max(destination > from ? destination - 1 : destination, 0), moved.count)
        moved.insert(download, at: to)
        return DownloadLibrary(downloads: moved)
    }

    /// Puts a download at the head of the queue, because a reader is waiting to read it.
    ///
    /// `offline-downloads`' *Reading while downloading* is about a reader not waiting for
    /// the last byte before the first page. The queue made that worse than it had to be:
    /// tapping *Read* appended to the **back** of the list and then waited, so on a metered
    /// link — where the bound is one — a reader wanting a five-megabyte comic waited out a
    /// four-hundred-megabyte one they had queued for later and were not reading.
    ///
    /// Order, not priority: nothing is cancelled, nothing is preempted, and a running
    /// download keeps its slot. `offline-downloads` gives the reader the queue's order
    /// anyway — "per-item and global pause, resume, cancel, and **reorder**" — and this is
    /// that same reorder, asked for by opening a book rather than by dragging a row.
    ///
    /// Only among the queued, for ``moving(_:later:)``'s reason: a running download has
    /// already started and a finished one has no order left to have. A download that is
    /// already at the head is left exactly where it is.
    public func promoting(_ id: Download.ID) -> DownloadLibrary {
        guard let download = self[id], download.state == .queued else { return self }
        guard let head = downloads.first(where: { $0.state == .queued }), head.id != id else {
            return self
        }
        var moved = downloads.filter { $0.id != id }
        guard let at = moved.firstIndex(where: { $0.state == .queued }) else { return self }
        moved.insert(download, at: at)
        return DownloadLibrary(downloads: moved)
    }

    /// Forgets a download. The file is the caller's to delete.
    public func removing(_ id: Download.ID) -> DownloadLibrary {
        DownloadLibrary(downloads: downloads.filter { $0.id != id })
    }

    /// Forgets everything a source contributed, for when the source itself is removed.
    /// Moves a queued download one place earlier or later.
    ///
    /// `offline-downloads` requires "per-item and global pause, resume, cancel, and
    /// reorder". One place at a time rather than a drag: the list is short, the action is
    /// undoable by doing it again, and a swap needs no gesture recogniser to be reachable
    /// by a screen reader.
    ///
    /// Only among the queued. A running download has already started, and a finished one
    /// has no order left to have.
    public func moving(_ id: Download.ID, later: Bool) -> DownloadLibrary {
        let queued = downloads.filter { $0.state == .queued }
        guard let at = queued.firstIndex(where: { $0.id == id }) else { return self }
        let to = later ? at + 1 : at - 1
        guard queued.indices.contains(to) else { return self }

        var reordered = queued
        reordered.insert(reordered.remove(at: at), at: to)

        var next = 0
        return DownloadLibrary(downloads: downloads.map { download in
            guard download.state == .queued else { return download }
            defer { next += 1 }
            return reordered[next]
        })
    }

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

    /// Records that the bytes arrived and were not a publication, and decides what next.
    ///
    /// `offline-downloads`: "when a download completes … its integrity is verified before
    /// it is marked available offline, and **a failed verification re-queues it once**".
    /// Once, and this is the whole of it: the first corrupt arrival goes back in the queue
    /// to be fetched again, because a truncated transfer is the likeliest cause and a
    /// second fetch is the cheapest way to find out. The second corrupt arrival is the
    /// server's answer rather than the network's, and the download is marked failed with
    /// the reason the reader can read.
    ///
    /// Separate from ``failing(_:reason:)`` because the two failures are not the same
    /// event. That one counts transfers that never arrived and allows three; this counts
    /// arrivals that were not a book and allows one more. Sharing a counter would let three
    /// corrupt downloads be re-fetched, or a flaky network burn the verification's only
    /// second chance before the bytes ever landed.
    public func failingVerification(_ id: Download.ID, reason: String) -> DownloadLibrary {
        DownloadLibrary(downloads: downloads.map { each in
            guard each.id == id else { return each }
            var changed = each
            changed.verificationFailures += 1
            changed.state = changed.verificationFailures <= Self.verificationLimit
                ? .queued
                // As though every transfer attempt were spent, so the queue stops asking.
                : .failed(reason: reason, attempts: Self.attemptLimit)
            return changed
        })
    }

    /// Whether a download whose bytes did not verify has its one re-queue left.
    public static func shouldRequeueAfterVerification(_ download: Download) -> Bool {
        download.verificationFailures < verificationLimit
    }

    /// One, from `offline-downloads`' "re-queues it once".
    public static let verificationLimit = 1

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

/// What is stopping the download queue.
///
/// Three situations with three different remedies, which is why `offline-downloads` requires
/// a held queue to name one rather than simply stopping: Wi-Fi returns by itself, the reader's
/// own maximum is theirs to raise, and a full device is neither. A stalled list that explains
/// none of them is the worst of the four.
///
/// Here rather than on the queue so a screen that holds no queue can draw it. Android's
/// `DownloadHold` is the same three cases.
public enum DownloadHold: Sendable, Equatable, CaseIterable {
    /// The device itself is short of room, whatever the reader's own limit says.
    case outOfSpace

    case waitingForWifi

    /// The reader's own maximum download size is reached.
    case storageFull
}
