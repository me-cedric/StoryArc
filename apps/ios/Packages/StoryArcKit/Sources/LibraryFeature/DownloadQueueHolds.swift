internal import Formats
public import StoryArcCore

/// Why the download queue is or is not allowed to move bytes right now.
///
/// Split out of ``DownloadQueue`` because that file had reached its own 400-line cap and
/// this is a seam that was already there: everything here answers one question — may the
/// queue run — and none of it moves a byte. The queue proper starts transfers, lands them
/// and records them; this decides whether it may.
///
/// The two stored flags this reads live on the type itself, because a stored property
/// cannot be declared in an extension.
extension DownloadQueue {
    /// What is stopping the queue.
    public enum Held: Sendable, Equatable {
        case waitingForWifi
        case storageFull

        /// The device itself is short of room, whatever the reader's own limit says.
        case outOfSpace
    }

    /// Asks the volume how much room is left, and remembers the answer.
    func refreshHeadroom() {
        spaceIsLow = StorageHeadroom.isLow(free: store?.availableBytes())
    }

    /// Why the queue is not starting anything, if it is not.
    ///
    /// Nil when it may run. `offline-downloads` requires a held queue to *say* what it is
    /// waiting for — "waiting for Wi-Fi", "the storage limit is reached" and "the device is
    /// full" are three different situations with three different remedies, and a stalled
    /// list that explains none of them is the worst of the four.
    ///
    /// The device's own shortage is answered first. The other two are situations the reader
    /// chose and can unchoose from the settings screen; this one is a fact about the phone,
    /// and it is the one that has to be said out loud before either of the others is worth
    /// mentioning.
    public var held: Held? {
        if spaceIsLow { return .outOfSpace }
        let current = settings()
        if current.downloadOverWifiOnly, network.isCellular { return .waitingForWifi }
        guard let limit = current.maximumDownloadBytes else { return nil }
        return library.bytesOnDisk >= limit ? .storageFull : nil
    }

    /// Re-examines a held queue.
    ///
    /// Called when the network or the settings change. `offline-downloads` promises
    /// downloads "resume automatically when [Wi-Fi] returns", and automatically means
    /// without the reader going back to the screen. The same is true of room: a reader who
    /// deletes a film comes back to a queue that started again by itself.
    public func reconsider() { pump() }

    /// Stops the queue because the device is full, and says so on every row.
    ///
    /// `offline-downloads`' *Device storage is low*, all three clauses:
    ///
    /// - **"pauses downloads"** — every queued and running transfer becomes
    ///   ``Download/Pause/outOfSpace``, which is the state and the sentence that have been
    ///   in the app, translated, and unreachable since the queue was written.
    /// - **"evicts the cover cache before any downloaded publication"** — the cache goes,
    ///   once. It is the only thing here the app may throw away without asking, because
    ///   every byte of it can be drawn again from a file the reader still has.
    /// - **"never deletes a download without asking"** — nothing below deletes anything.
    ///   The bytes already fetched stay where they are and the transfer resumes from them
    ///   when there is room, which is the whole point of pausing rather than cancelling.
    func holdForSpace() {
        for id in running.keys { running[id]?.cancel() }
        running.removeAll()
        library = library.pausingForSpace()
        store?.save(library)
        guard !coversEvicted else { return }
        coversEvicted = true
        CoverCache().clear()
    }

    /// Puts back what was only waiting for room, once there is some.
    func releaseSpaceHolds() {
        coversEvicted = false
        let waiting = library.resumingAfterSpace()
        guard waiting != library else { return }
        library = waiting
        store?.save(library)
    }
}
