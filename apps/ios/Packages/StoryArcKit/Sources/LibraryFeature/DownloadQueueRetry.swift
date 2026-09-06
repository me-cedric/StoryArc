public import StoryArcCore

/// A retry handed to the queue that can run it, from the one screen that has no queue.
///
/// The Downloads destination writes the download store and owns no ``DownloadQueue``: the
/// only queue the app builds is `@State` on a catalogue page, alive while that page is. So a
/// failed row's *Retry* there can mark the record `queued` — which is ``resume(_:)`` minus
/// the pump — and then has nowhere to send the pump. Android found the hole first, fixing the
/// same row a day earlier: `DownloadQueue.reconsider()` had no callers on either platform,
/// and a re-queued record was picked up only when a reader next enqueued something from a
/// catalogue. ``reconsider()`` now has its own callers — a change of network, and room freed
/// by a removal — but none of them is a queue this screen can name. This is that caller.
///
/// Every queue registers itself while it is alive, weakly, and ``retry(_:)`` asks the first
/// of them that holds the record as failed to resume it — and only that one, because two
/// catalogue pages can be alive at once over the same store. When one does, the transfer
/// starts now.
/// When none is alive, the store's `queued` record stands, and the next queue built reads it
/// in its `init` and pumps — which is how every record that was mid-flight when the app died
/// comes back. `DownloadQueueRetryTests` proves both ends.
///
/// Weak, and pruned on every ask, so a queue's lifetime stays its page's: a strong registry
/// would keep a catalogue's queue — and its client, and its credential closure — alive after
/// the page that made it had gone.
extension DownloadQueue {
    /// The queues alive right now. Isolated with the class, so nothing here races.
    private static var live: [Alive] = []

    /// A weak hold, because an array cannot hold `weak var` directly.
    private struct Alive {
        weak var queue: DownloadQueue?
    }

    /// Called once, from `init`, after the record has been read.
    func remember() {
        Self.live = Self.live.filter { $0.queue != nil } + [Alive(queue: self)]
    }

    /// Puts a failed download back in the queue, on whichever live queue holds it.
    ///
    /// Failed only. A paused record is left exactly as it is: a row paused for Wi-Fi or for
    /// space would be re-queued here only to pause again on the next pump, and one paused by
    /// the reader is paused because they asked. Returns whether a queue took it — `false`
    /// means the caller's own write to the store is the whole of the retry until a queue is
    /// next built, and the caller is expected to have made that write first.
    @discardableResult
    public static func retry(_ id: Download.ID) -> Bool {
        live = live.filter { $0.queue != nil }
        // The first queue that holds it, and only that one. Two catalogue pages can be alive
        // at once — a split view, or a page kept in a navigation stack — and both read the
        // same store, so both hold the same failed record; resuming it on each would start
        // two transfers of one download and leak the second's continuation. One tap, one
        // transfer; the store they share is written by the one that ran it.
        for alive in live {
            guard let queue = alive.queue, case .failed = queue.library[id]?.state else { continue }
            queue.resume(id)
            return true
        }
        return false
    }
}
