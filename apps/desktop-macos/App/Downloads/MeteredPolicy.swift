import Foundation
import Network
import StoryArcCore

/// What the system says of the connection, in the four answers the rule needs.
///
/// `design.md` Decision 9: on a Mac, metered is Low Data Mode or a path the system calls
/// expensive (a phone's hotspot). `desktop-experience`: a connection the system does not
/// describe is not metered, so ``unknown`` downloads as ``unmetered`` does.
enum NetworkCondition: Sendable, Equatable {
    case unknown
    case offline
    case unmetered
    case metered

    static func of(isSatisfied: Bool, isExpensive: Bool, isConstrained: Bool) -> NetworkCondition {
        guard isSatisfied else { return .offline }
        return isExpensive || isConstrained ? .metered : .unmetered
    }
}

/// Something that reports the connection: the system's path monitor, or a test's fake.
@MainActor
protocol PathObserving: AnyObject {
    func start(_ report: @escaping @MainActor (NetworkCondition) -> Void)
    func stop()
}

/// `NWPathMonitor`, read into a ``NetworkCondition``.
@MainActor
final class SystemPathObserver: PathObserving {
    private let monitor = NWPathMonitor()

    func start(_ report: @escaping @MainActor (NetworkCondition) -> Void) {
        monitor.pathUpdateHandler = { path in
            let condition = NetworkCondition.of(
                isSatisfied: path.status == .satisfied, isExpensive: path.isExpensive,
                isConstrained: path.isConstrained
            )
            Task { @MainActor in report(condition) }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    func stop() { monitor.cancel() }
}

/// The connection now, and a listener told once per change.
@MainActor
@Observable
final class MeteredMonitor {
    private(set) var condition: NetworkCondition = .unknown
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let observer: any PathObserving

    var isMetered: Bool { condition == .metered }

    init(observer: any PathObserving = SystemPathObserver()) {
        self.observer = observer
        observer.start { [weak self] condition in self?.note(condition) }
    }

    /// Internal rather than private so the screen catalogue can pin what it draws.
    func note(_ condition: NetworkCondition) {
        guard condition != self.condition else { return }
        self.condition = condition
        onChange?()
    }
}

/// Which downloads the metered rule holds back, and which it lets go.
///
/// Pure, so each scenario is a test (`MeteredPolicyTests`). The queue is StoryArcKit's; its
/// own Wi-Fi rule reads a cellular interface, which a Mac on a hotspot's Wi-Fi does not
/// have, so the Mac decides here from the metered flags and pauses and resumes through the
/// queue's public calls. Only downloads this rule held are ever released by it: a pause the
/// reader asked for stays.
enum MeteredPolicy {
    struct Decision: Equatable {
        /// To pause now.
        var hold: Set<Download.ID> = []
        /// Held by this rule, and free to run again.
        var release: Set<Download.ID> = []
        /// Held by this rule, and no longer in the queue.
        var forget: Set<Download.ID> = []
    }

    /// Why a download in the queue is waiting, said in grey.
    enum Reason: Equatable {
        case metered
        case offline
    }

    static func mayRun(wifiOnly: Bool, condition: NetworkCondition, byHand: Bool) -> Bool {
        byHand || !(wifiOnly && condition == .metered)
    }

    static func decide(
        _ downloads: [Download], held: Set<Download.ID>, byHand: Set<Download.ID>, wifiOnly: Bool,
        condition: NetworkCondition
    ) -> Decision {
        var decision = Decision()
        let present = Set(downloads.map(\.id))
        decision.forget = held.subtracting(present)
        for download in downloads {
            let runs = mayRun(wifiOnly: wifiOnly, condition: condition, byHand: byHand.contains(download.id))
            if held.contains(download.id) {
                if runs { decision.release.insert(download.id) }
            } else if download.state.isActive, !runs {
                decision.hold.insert(download.id)
            }
        }
        return decision
    }

    static func reason(for id: Download.ID, held: Set<Download.ID>, condition: NetworkCondition) -> Reason? {
        if held.contains(id) { return .metered }
        return condition == .offline ? .offline : nil
    }
}
