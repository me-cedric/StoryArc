public import Foundation

internal import Network

/// Whether the connection is one to be careful with, and a way to be told when it changes.
///
/// `network-share` asks the same question before streaming: on such a connection the reader
/// confirms first.
///
/// `offline-downloads`: the bound is "lowered on a metered connection", and "when the
/// platform's data saver or Low Data Mode is active ... the app treats the connection as
/// metered regardless of its own setting". `isConstrained` is Low Data Mode; `isExpensive`
/// is cellular and personal hotspot. Both mean the same thing here: use less of it.
///
/// The two answers are kept rather than the `NWPath` they came from. The monitor's own
/// update handler is the callback this type needs — no publisher and no observation
/// framework is added for it — and a stored pair of answers is what lets ``note(careful:
/// cellular:)`` be the one door both the monitor and a test come through.
@MainActor
final class NetworkCost {
    private let monitor = NWPathMonitor()

    /// Told after every change, so a held download queue can look again.
    ///
    /// Owners hold themselves weakly here: this object belongs to the one that sets the
    /// closure, and a strong capture would be a cycle.
    var onChange: (() -> Void)?

    /// True until the monitor has an answer, which errs toward using less.
    private(set) var isCareful = true

    /// Whether the only way out is cellular.
    ///
    /// Separate from ``isCareful``: Low Data Mode over Wi-Fi is careful but is still Wi-Fi,
    /// and `offline-downloads`' "download over Wi-Fi only" is a question about the medium
    /// rather than about the cost. True until the monitor has an answer, for the same
    /// reason ``isCareful`` is.
    private(set) var isCellular = true

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.note(
                    careful: path.isConstrained || path.isExpensive,
                    cellular: !path.usesInterfaceType(.wifi)
                        && !path.usesInterfaceType(.wiredEthernet)
                )
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    deinit {
        monitor.cancel()
    }

    /// Records the connection and tells whoever is listening, when it changed.
    ///
    /// The monitor calls this, and so does a test: a `NWPath` cannot be built, so injecting
    /// the answer is the only way to assert what the queue does with it.
    ///
    /// **A report that says what the last one said is dropped here.** `NWPathMonitor` fires
    /// on every property of the path, most of which this type does not read, and the listener
    /// is a download queue whose ``DownloadQueue/pump()`` asks the volume how much room is
    /// left. That is a filesystem stat on the main actor, and paying it for a report that
    /// changed nothing is the cost this guard exists to refuse. The same argument the cached
    /// ``DownloadQueue/spaceIsLow`` makes: a stat per notice is a cost a screen should not pay.
    func note(careful: Bool, cellular: Bool) {
        guard careful != isCareful || cellular != isCellular else { return }
        isCareful = careful
        isCellular = cellular
        onChange?()
    }
}
