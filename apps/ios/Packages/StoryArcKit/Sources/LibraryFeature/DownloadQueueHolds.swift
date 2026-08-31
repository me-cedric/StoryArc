public import Catalogue
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
        // Not held when something in the queue carries a metered override: one granted
        // publication is running, and a queue that reported itself stopped while bytes
        // were arriving would be the lie this property exists to prevent.
        if current.downloadOverWifiOnly, network.isCellular, !hasOverriddenPending {
            return .waitingForWifi
        }
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

    /// Whether the reader has to be asked before this one is queued.
    ///
    /// `offline-downloads`' *Overriding once*. The answer is ``MeteredDownload``'s; what
    /// this adds is the two facts it needs — whether the link is one to be careful with,
    /// and whether this publication already carries a grant.
    public func needsMeteredConfirmation(_ entry: OpdsEntry) -> Bool {
        MeteredDownload.needsConfirmation(
            isMetered: network.isCareful,
            isOverridden: overridden.contains(entry.id)
        )
    }

    /// What the confirmation can state about the size, or `nil` when nothing can.
    ///
    /// `offline-downloads` asks the confirmation to state the size, and states elsewhere
    /// that a size is shown only when the server gave one — "a fabricated one is worse than
    /// an honest blank". An OPDS acquisition link carries no length, so the honest answer
    /// before a first download is usually nothing, and the dialog says so in words rather
    /// than showing a number nobody supplied.
    public func statedBytes(of entry: OpdsEntry) -> Int64? {
        library[entry.id]?.expectedBytes
    }

    /// Whether this one may start over the connection the device is on.
    func mayStart(_ download: Download) -> Bool {
        MeteredDownload.mayStart(
            wifiOnly: settings().downloadOverWifiOnly,
            isMetered: network.isCellular,
            isOverridden: overridden.contains(download.id)
        )
    }

    /// Whether anything still to do carries a grant.
    var hasOverriddenPending: Bool {
        library.pending.contains { overridden.contains($0.id) }
    }
}
