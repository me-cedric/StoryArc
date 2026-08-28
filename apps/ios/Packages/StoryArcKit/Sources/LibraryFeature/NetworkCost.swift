public import Foundation

internal import Network

/// Whether the connection is one to be careful with.
///
/// `network-share` asks the same question before streaming: on such a connection the reader
/// confirms first.
///
/// `offline-downloads`: the bound is "lowered on a metered connection", and "when the
/// platform's data saver or Low Data Mode is active ... the app treats the connection as
/// metered regardless of its own setting". `isConstrained` is Low Data Mode; `isExpensive`
/// is cellular and personal hotspot. Both mean the same thing here: use less of it.
@MainActor
final class NetworkCost {
    private let monitor = NWPathMonitor()
    private var path: NWPath?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.path = path }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    deinit {
        monitor.cancel()
    }

    /// True until the monitor has an answer, which errs toward using less.
    var isCareful: Bool {
        guard let path else { return true }
        return path.isConstrained || path.isExpensive
    }

    /// Whether the only way out is cellular.
    ///
    /// Separate from ``isCareful``: Low Data Mode over Wi-Fi is careful but is still Wi-Fi,
    /// and `offline-downloads`' "download over Wi-Fi only" is a question about the medium
    /// rather than about the cost.
    var isCellular: Bool {
        guard let path else { return true }
        return !path.usesInterfaceType(.wifi) && !path.usesInterfaceType(.wiredEthernet)
    }
}
