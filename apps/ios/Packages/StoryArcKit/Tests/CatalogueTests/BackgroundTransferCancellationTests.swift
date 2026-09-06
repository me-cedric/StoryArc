import Foundation
import Synchronization
import Testing

import Catalogue

/// Cancelling the caller has to stop the system's transfer, not merely stop waiting for it.
///
/// `offline-downloads`' *Wi-Fi only* is enforced by the queue cancelling the task that awaits
/// a download. The await was a bare `withCheckedThrowingContinuation`, which cancellation does
/// not reach: the `URLSessionDownloadTask` ran on, the whole file arrived over cellular, and
/// the record that said "waiting for Wi-Fi" was then marked finished. The setting a reader
/// chose to protect their mobile allowance spent it instead.
///
/// The address resolves to nothing, so nothing here depends on a server. What is asserted is
/// what the caller is told, and a caller told `CancellationError` is one whose system task was
/// cancelled.
///
/// **Nothing here awaits the transfer.** The failure being pinned is a wait that never ends —
/// an unresumed continuation — so the outcome is read out of a box the transfer writes to, and
/// the test waits a bounded five seconds for it. Awaiting the task itself would hang the whole
/// suite on the very bug the test exists to catch.
@Suite("A cancelled transfer stops the system's task")
struct BackgroundTransferCancellationTests {
    @Test("Cancelling the caller cancels the transfer instead of letting it land")
    func cancellationReachesTheSystemTask() async throws {
        let transfers = BackgroundTransfers.shared()
        let address = try #require(URL(string: "https://example.invalid/harbour-lights-07.epub"))
        let told = Mutex<String?>(nil)

        let transfer = Task {
            do {
                _ = try await transfers.download(
                    URLRequest(url: address),
                    named: "held-\(UUID().uuidString)"
                )
                told.withLock { $0 = "landed" }
            } catch is CancellationError {
                told.withLock { $0 = "cancelled" }
            } catch {
                told.withLock { $0 = String(describing: type(of: error)) }
            }
        }
        transfer.cancel()

        // Five seconds, not the half second this waited until 2026-09-06. The box is written
        // in milliseconds when the machine is idle, so a passing run costs the same as before;
        // the budget only matters on a loaded host. Half a second was not enough there, and the
        // test failed roughly one run in four locally and on every GitHub `macos-26` runner.
        for _ in 0..<500 where told.withLock({ $0 }) == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(
            told.withLock { $0 } == "cancelled",
            "A cancelled transfer did not stop the system's task within five seconds."
        )
    }
}
