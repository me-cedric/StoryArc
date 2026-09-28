internal import StoryArcCore

/// What a reader is told before a whole shelf is fetched.
///
/// `collections-and-reading-lists`: downloading a collection or a reading list "states the
/// item count and total size before starting". Both numbers describe the fetch, not the shelf
/// — what is already on the device is neither fetched again nor weighed again, so a reader who
/// has most of a collection already is quoted the megabytes they are about to spend rather
/// than the megabytes the collection occupies.
///
/// A value beside the menu rather than two lines inside a button's action, because a button's
/// action cannot be asked what it would have said. Android's `BulkDownloadAsk` answers the
/// same.
struct BulkDownloadAsk: Equatable {
    /// What would be fetched: the selection, less what the device already holds.
    let ids: Set<String>

    /// What those, and only those, weigh.
    let bytes: Int64

    /// The question to put to the reader, or nil when there is nothing to fetch.
    ///
    /// Nil rather than a prompt counting nought: a shelf already on the device gets a sentence
    /// saying so, which is a different answer from a confirmation the reader would have to
    /// cancel.
    static func of(
        _ selection: Set<String>,
        onDevice: Set<String>,
        weigh: (Set<String>) -> Int64
    ) -> BulkDownloadAsk? {
        let ids = BulkSelection.downloading(selection, onDevice: onDevice)
        guard !ids.isEmpty else { return nil }
        return BulkDownloadAsk(ids: ids, bytes: weigh(ids))
    }
}
