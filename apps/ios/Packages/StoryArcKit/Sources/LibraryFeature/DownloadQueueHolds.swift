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
    /// How many transfers run at once.
    ///
    /// Two on an ordinary connection: enough that a slow server does not stall the whole
    /// queue, few enough that a reader's bandwidth is not divided six ways. One on a
    /// metered or constrained connection, which is what `offline-downloads` means by
    /// lowering the bound — Low Data Mode and a personal hotspot both land here.
    ///
    /// Here rather than on the queue proper because it answers this file's one question —
    /// may the queue run, and how much — out of the same ``NetworkCost`` that ``mayStart(_:)``
    /// reads. It moved to make room for the observer that wakes a held queue.
    public var concurrency: Int { network.isCareful ? 1 : 2 }

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
    /// Read from the records rather than from the connection, and that is the whole of it:
    /// ``pump()`` writes the reason onto every row it holds, so the queue's live answer and
    /// the one a screen draws cannot disagree. ``DownloadLibrary/hold(limit:)`` is the rule,
    /// asserted there, and a screen that holds no queue asks it the same question.
    public var held: DownloadHold? {
        library.hold(limit: settings().maximumDownloadBytes)
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

    /// Holds every download the connection no longer permits, and puts back the rest.
    ///
    /// `offline-downloads`' *Wi-Fi only* has two halves — downloads "pause and state that
    /// they are waiting for Wi-Fi, and resume automatically when it returns" — and the queue
    /// answered only the second. ``pump()`` started transfers and never stopped one, so a
    /// reader who set the setting, began a download on Wi-Fi and walked out of range kept
    /// downloading over cellular. The setting they chose to protect their data stopped
    /// protecting it at the moment a transfer was running, which is the moment it costs them
    /// money.
    ///
    /// The mirror of ``holdForSpace()`` and ``releaseSpaceHolds()``, in one call because the
    /// rule decides both directions at once — see
    /// ``DownloadLibrary/reconsideringWifi(permits:)``. **Nothing is written when nothing
    /// changed**, which is what makes a flapping connection cheap: a report that says what
    /// the last one said never reaches here at all, and one that does costs a write only when
    /// a record actually moved.
    ///
    /// Cancelling is not deleting. The record and the bytes counted against it stay, and the
    /// download is started again when Wi-Fi returns. What the app cannot yet do is start it
    /// again *from* those bytes: there is no Range request anywhere in either tree, so a
    /// resumed transfer begins at zero.
    func holdForConnection() {
        let next = library.reconsideringWifi { mayStart($0) }
        guard next != library else { return }
        library = next
        // Cancelled after the record is decided, so a transfer that ends while this runs
        // finds the row already paused. An id that is not running cancels nothing.
        for download in next.downloads where download.state == .paused(.waitingForWiFi) {
            running.removeValue(forKey: download.id)?.cancel()
        }
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
}
