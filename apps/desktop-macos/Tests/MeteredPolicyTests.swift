import Foundation
import StoryArcCore
import Testing

@testable import StoryArc

/// Task 3.11, test first: the metered rule over a fake path monitor.
///
/// `desktop-experience`, *Metered connections*: a connection the system marks metered holds
/// back the downloads the reader did not start by hand while the Wi-Fi-only rule is on, and
/// says why in grey; one started by hand still runs; a connection the system does not
/// describe is not metered; a change mid-download pauses what the rule holds back and
/// resumes it when an unmetered connection returns; no connection leaves the queue waiting.
@MainActor
@Suite("Metered connections")
struct MeteredPolicyTests {
    private func download(_ id: String, _ state: Download.State = .queued) -> Download {
        Download(
            id: id, title: id, remote: URL(filePath: "/\(id)"), mediaType: "application/zip", state: state
        )
    }

    // MARK: - The monitor

    @Test("Before the system answers, the connection is unknown and not metered")
    func unknownIsNotMetered() {
        let path = FakePathObserver()
        let monitor = MeteredMonitor(observer: path)
        #expect(monitor.condition == .unknown)
        #expect(!monitor.isMetered)
    }

    @Test("The monitor follows each report and tells its listener once per change")
    func monitorFollowsReports() {
        let path = FakePathObserver()
        let monitor = MeteredMonitor(observer: path)
        var changes = 0
        monitor.onChange = { changes += 1 }
        path.report(.metered)
        #expect(monitor.isMetered)
        path.report(.metered)
        path.report(.unmetered)
        #expect(!monitor.isMetered)
        #expect(changes == 2)
    }

    @Test("A path is metered when the system calls it expensive or constrained, and offline when unsatisfied")
    func pathReading() {
        #expect(NetworkCondition.of(isSatisfied: true, isExpensive: true, isConstrained: false) == .metered)
        #expect(NetworkCondition.of(isSatisfied: true, isExpensive: false, isConstrained: true) == .metered)
        #expect(NetworkCondition.of(isSatisfied: true, isExpensive: false, isConstrained: false) == .unmetered)
        #expect(NetworkCondition.of(isSatisfied: false, isExpensive: true, isConstrained: true) == .offline)
    }

    // MARK: - The policy

    @Test("Metered, with the rule on: queued and running downloads are held, and the queue says why")
    func meteredHolds() {
        let decision = MeteredPolicy.decide(
            [download("a"), download("b", .running), download("c", .finished)],
            held: [], byHand: [], wifiOnly: true, condition: .metered
        )
        #expect(decision.hold == ["a", "b"])
        #expect(decision.release.isEmpty)
        #expect(MeteredPolicy.reason(for: "a", held: decision.hold, condition: .metered) == .metered)
    }

    @Test("Metered: a download started by hand still runs")
    func byHandRuns() {
        let decision = MeteredPolicy.decide(
            [download("a"), download("b")], held: [], byHand: ["b"], wifiOnly: true, condition: .metered
        )
        #expect(decision.hold == ["a"])
        #expect(MeteredPolicy.mayRun(wifiOnly: true, condition: .metered, byHand: true))
    }

    @Test("Metered with the rule off: nothing is held")
    func ruleOff() {
        let decision = MeteredPolicy.decide([download("a")], held: [], byHand: [], wifiOnly: false, condition: .metered)
        #expect(decision.hold.isEmpty)
    }

    @Test("Unmetered and unknown: nothing is held, and what was held is released", arguments: [
        NetworkCondition.unmetered, .unknown,
    ])
    func unmeteredReleases(condition: NetworkCondition) {
        let decision = MeteredPolicy.decide(
            [download("a", .paused(.byReader)), download("b")], held: ["a"], byHand: [], wifiOnly: true,
            condition: condition
        )
        #expect(decision.hold.isEmpty)
        #expect(decision.release == ["a"])
        #expect(MeteredPolicy.reason(for: "a", held: [], condition: condition) == nil)
    }

    @Test("A change to metered mid-download pauses it, and the return of an unmetered link resumes it")
    func midDownloadChange() {
        let running = [download("a", .running)]
        let paused = MeteredPolicy.decide(running, held: [], byHand: [], wifiOnly: true, condition: .metered)
        #expect(paused.hold == ["a"])
        let back = MeteredPolicy.decide(
            [download("a", .paused(.byReader))], held: paused.hold, byHand: [], wifiOnly: true, condition: .unmetered
        )
        #expect(back.release == ["a"])
    }

    @Test("A download the reader paused is never released by the network")
    func readerPauseStays() {
        let decision = MeteredPolicy.decide(
            [download("a", .paused(.byReader))], held: [], byHand: [], wifiOnly: true, condition: .unmetered
        )
        #expect(decision.release.isEmpty)
    }

    @Test("No connection holds nothing and says the queue waits, in grey")
    func offline() {
        let decision = MeteredPolicy.decide([download("a")], held: [], byHand: [], wifiOnly: true, condition: .offline)
        #expect(decision.hold.isEmpty)
        #expect(MeteredPolicy.reason(for: "a", held: [], condition: .offline) == .offline)
    }

    @Test("A held download that left the queue is forgotten")
    func forgetsGone() {
        let decision = MeteredPolicy.decide([], held: ["gone"], byHand: [], wifiOnly: true, condition: .metered)
        #expect(decision.forget == ["gone"])
    }
}

/// A path monitor a test drives: each `report` is what the system would have said.
@MainActor
final class FakePathObserver: PathObserving {
    private var handler: ((NetworkCondition) -> Void)?
    private(set) var isStopped = false

    func start(_ report: @escaping @MainActor (NetworkCondition) -> Void) { handler = report }
    func stop() { isStopped = true }
    func report(_ condition: NetworkCondition) { handler?(condition) }
}
