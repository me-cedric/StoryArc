public import Foundation

internal import Network

/// Whether the device has a network path, as a stream.
///
/// **The observing half of ``SourceReachability``, which owns the deciding half.** That split
/// is the point: `NWPathMonitor` needs a real device and a real network, so a test that drove
/// it would be a test nobody runs — the edge detection, the reading guard and the
/// "something is away" condition all live in `StoryArcCore` and take a signal as an argument.
/// This is the one piece that cannot be tested without a device, and it is deliberately the
/// smallest piece: start a monitor, report `satisfied`, cancel on termination.
///
/// Separate from ``NetworkCost``, which watches the same framework for a different question.
/// Two monitors rather than one shared object because the questions have different lifetimes —
/// the cost is asked synchronously whenever a download is considered, and this is consumed by
/// a `.task` that ends with the view. A single monitor would have to outlive both and answer
/// both, which is how one of them ends up reading a stale path.
enum NetworkPaths {

    /// `true` when a path is satisfied, reported on every change.
    ///
    /// The first report describes the network **as it already is** rather than a change to it,
    /// which is why ``SourceReachability/triggers(from:startingFrom:)`` assumes a path before
    /// the stream opens: without that, launching with Wi-Fi on would read as a regain and probe
    /// every configured source a moment after the library already did.
    static func satisfied() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            monitor.start(queue: .global(qos: .utility))
            continuation.onTermination = { _ in monitor.cancel() }
        }
    }
}
