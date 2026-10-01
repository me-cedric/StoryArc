public import Foundation

/// What the storage view asks of a library of downloads: how much, from where, and which
/// ones are the biggest.
///
/// `offline-downloads` asks the storage view to state the total "broken down by source" and
/// to offer "a largest-first list, each removable". Split out of ``DownloadLibrary`` for the
/// line cap that file is already close to. Android's `DownloadLibrary.kt` carries the same
/// two answers.
extension DownloadLibrary {
    /// Every finished download, largest first — the order "what can I delete" is asked in.
    ///
    /// ``Persistence/ImportedCopies/imports(in:)`` already sorted this for imports alone;
    /// this is the same rule over every finished download, not only the imported ones.
    public var largestFirst: [Download] {
        finished.sorted { $0.downloadedBytes > $1.downloadedBytes }
    }

    /// Finished bytes, summed per source. `nil` keys a download with no source of its own.
    ///
    /// A dictionary rather than a sorted list: the storage view names each source through
    /// its own registry, which this type knows nothing about, so the naming and the
    /// ordering both belong to the caller.
    public var bytesBySource: [UUID?: Int64] {
        var totals: [UUID?: Int64] = [:]
        for download in finished {
            totals[download.sourceID, default: 0] += download.downloadedBytes
        }
        return totals
    }
}
