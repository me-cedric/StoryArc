import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What a queue row says about a transfer, beyond the bar.
///
/// `offline-downloads`: a queued publication is one whose "size is shown, and progress is
/// visible on the publication and in a single downloads view". The bar carried the second
/// half alone — a reader could see roughly how full a rectangle was and nothing else — so
/// the September sweep photographed three transfers stating no size and no percentage
/// between them (`ios-downloads-queue.png`).
@Suite("Download queue progress")
struct DownloadQueueProgressTests {

    private func download(
        expected: Int64?,
        downloaded: Int64,
        state: Download.State = .running
    ) -> Download {
        Download(
            id: "one",
            title: "Harbour Lights 03",
            remote: URL(string: "https://example.invalid/hl03.epub")!,
            mediaType: "application/epub+zip",
            state: state,
            expectedBytes: expected,
            downloadedBytes: downloaded
        )
    }

    /// The whole point: a size the server stated, and how far through it is.
    @Test("A sized transfer states both halves and the percentage")
    func sized() {
        let statement = DownloadQueueProgress.statement(
            for: download(expected: 8_400_000, downloaded: 3_100_000)
        )
        #expect(statement == .sized(percent: 37, downloaded: 3_100_000, expected: 8_400_000))
    }

    /// `expectedBytes` is `nil` when the server would not say. `Download` already refuses to
    /// fabricate a fraction there; this refuses to fabricate a total, and says what has
    /// actually landed instead — which is a real number and the only one there is.
    @Test("An unsized transfer states what has arrived, and no total")
    func unsized() {
        let statement = DownloadQueueProgress.statement(
            for: download(expected: nil, downloaded: 1_200_000)
        )
        #expect(statement == .unsized(downloaded: 1_200_000))
    }

    /// A transfer with a total but nothing through it yet is `0%`, not silence: the second
    /// row of the sweep's queue is exactly this, and a row that said nothing was
    /// indistinguishable from one that had failed to start.
    @Test("A transfer that has not started still states its size")
    func notStarted() {
        let statement = DownloadQueueProgress.statement(
            for: download(expected: 41_000_000, downloaded: 0, state: .queued)
        )
        #expect(statement == .sized(percent: 0, downloaded: 0, expected: 41_000_000))
    }

    /// Nothing known at all — no total, no bytes — has nothing honest to say, and the
    /// indeterminate bar is left to carry it alone.
    @Test("A transfer with no size and no bytes says nothing")
    func silent() {
        #expect(DownloadQueueProgress.statement(for: download(expected: nil, downloaded: 0)) == nil)
        #expect(DownloadQueueProgress.statement(for: download(expected: 0, downloaded: 0)) == nil)
    }

    /// **99%, not 100%, until it is actually finished.** Rounding to nearest is what makes
    /// 3.1 of 8.4 read as the 37% a person measures off the bar, and it is also what would
    /// let a transfer with 40 kB still to come announce itself complete. A reader who reads
    /// 100% and then watches the row sit there has been told the app is stuck.
    @Test("A nearly complete transfer never claims to be complete")
    func nearlyComplete() {
        let statement = DownloadQueueProgress.statement(
            for: download(expected: 10_000_000, downloaded: 9_999_000)
        )
        #expect(statement == .sized(percent: 99, downloaded: 9_999_000, expected: 10_000_000))
    }

    /// And a transfer that really has arrived reads 100%.
    @Test("Every byte through is a hundred percent")
    func complete() {
        let statement = DownloadQueueProgress.statement(
            for: download(expected: 10_000_000, downloaded: 10_000_000)
        )
        #expect(statement == .sized(percent: 100, downloaded: 10_000_000, expected: 10_000_000))
    }

    /// A server that over-reports is capped rather than believed: ``Download/fraction``
    /// already clamps, and the percentage is derived from it rather than recomputed.
    @Test("More bytes than the server promised is still a hundred percent")
    func overshoot() {
        let statement = DownloadQueueProgress.statement(
            for: download(expected: 1_000, downloaded: 4_000)
        )
        #expect(statement == .sized(percent: 100, downloaded: 4_000, expected: 1_000))
    }

    /// A failed row already carries its reason in red, and a percentage under it would be
    /// competing with the one thing a reader has to read there.
    @Test("A failed transfer states no progress")
    func failed() {
        let statement = DownloadQueueProgress.statement(
            for: download(
                expected: 2_200_000,
                downloaded: 190_000,
                state: .failed(reason: "The server did not answer in time.", attempts: 3)
            )
        )
        #expect(statement == nil)
    }

    /// A paused row says *why* it is paused, which is the sentence that matters there. The
    /// size still belongs to it: a reader deciding whether to wait for Wi-Fi is deciding
    /// about a number.
    @Test("A paused transfer keeps its size")
    func paused() {
        let statement = DownloadQueueProgress.statement(
            for: download(expected: 8_400_000, downloaded: 3_100_000, state: .paused(.waitingForWiFi))
        )
        #expect(statement == .sized(percent: 37, downloaded: 3_100_000, expected: 8_400_000))
    }
}
