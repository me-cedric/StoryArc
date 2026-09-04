public import StoryArcCore

/// What a transfer says about itself, over and above its bar.
///
/// `offline-downloads` asks that a queued publication have "its size shown, and progress
/// visible on the publication and in a single downloads view". The queue row carried the
/// second half and only the second half: a `ProgressView` and nothing beside it, so the
/// September sweep photographed three transfers between them stating no size, no byte
/// count and no percentage — `ios-downloads-queue.png`. A bar answers *roughly how far*
/// and cannot answer *how much*, which is the question a reader on a phone with 400 MB
/// free is actually asking.
///
/// A value rather than a formatted string, and here rather than in the view, for two
/// reasons. The rounding rule below is the sort of thing that is wrong in a way nobody
/// notices until a reader watches a row sit at 100% — so it is worth pinning in a test —
/// and the app target has no test target of its own, while this module has one.
///
/// The *rendering* stays with the view, because the strings live in the app's bundle.
public enum DownloadQueueProgress {

    /// What there is to say, which is not the same for every transfer.
    public enum Statement: Sendable, Equatable {
        /// The server stated a total, so the row can state both halves and the percentage.
        case sized(percent: Int, downloaded: Int64, expected: Int64)

        /// No total, so no percentage either — but bytes have landed, and that is a real
        /// number. ``Download/expectedBytes`` is `nil` precisely so that a fabricated total
        /// is never shown; this is the honest half of the same rule.
        case unsized(downloaded: Int64)
    }

    /// What this transfer's row should say beside its bar, or `nil` when nothing it knows
    /// is worth saying.
    ///
    /// Three transfers get `nil`. One that has failed, because its row already carries a
    /// plain-language reason and a percentage under that would compete with the only
    /// sentence there a reader has to read. One with neither a total nor a byte through it,
    /// because "0 bytes of an unknown total" is a way of writing *nothing is known* at
    /// length. And a finished one, which is not in this list at all.
    public static func statement(for download: Download) -> Statement? {
        if case .failed = download.state { return nil }
        if download.state.isFinished { return nil }

        if let expected = download.expectedBytes, expected > 0 {
            return .sized(
                percent: percent(of: download),
                downloaded: download.downloadedBytes,
                expected: expected
            )
        }
        guard download.downloadedBytes > 0 else { return nil }
        return .unsized(downloaded: download.downloadedBytes)
    }

    /// How far through, as a whole number a person reads off the bar.
    ///
    /// Derived from ``Download/fraction``, which already clamps a server that over-reports,
    /// rather than dividing a second time — two divisions of the same pair are two chances
    /// to disagree with the bar drawn from the first.
    ///
    /// **Rounded to nearest, then held at 99 until every byte is through.** Rounding is
    /// what makes 3.1 MB of 8.4 read as the 37% a reader measures off the bar rather than
    /// 36. It is also what would let a transfer with 40 kB still to come announce itself
    /// complete — and a row that reads 100% and then sits there has told the reader the app
    /// is stuck, which is the one thing a progress line exists to prevent.
    private static func percent(of download: Download) -> Int {
        guard let fraction = download.fraction else { return 0 }
        if fraction >= 1 { return 100 }
        return min(99, Int((fraction * 100).rounded()))
    }
}
