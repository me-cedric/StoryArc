import Foundation
import Testing

@testable import StoryArcCore

/// When a regained network or a returning app asks an away source again, and when it must
/// not.
///
/// Android's `SourceReachabilityTest` asserts the same cases, case for case.
@Suite("Source reachability")
struct SourceReachabilityTests {

    private let moment = Date(timeIntervalSince1970: 1_000)

    private func source(_ state: SourceConnectionState) -> Source {
        Source(displayName: "Shelf", kind: .kavitaServer, state: state)
    }

    private var away: [Source] { [source(.unreachable(since: moment))] }

    // MARK: - The two occasions

    @Test("A regained network retries a source that is away")
    func regainedNetworkProbes() {
        #expect(SourceReachability.shouldProbe(
            on: .connectivityRegained, sources: away, isReading: false
        ))
    }

    @Test("Returning to the foreground retries a source that is away")
    func foregroundProbes() {
        #expect(SourceReachability.shouldProbe(
            on: .returnedToForeground, sources: away, isReading: false
        ))
    }

    @Test("Both occasions are one decision, not two")
    func bothOccasionsAgree() {
        // `sources` grants the immediate retry to a regained network *and* to a returning
        // app. One gate for both is what keeps the reading guard below on both of them, so
        // every trigger is asserted through it rather than only the two named above.
        for trigger in RetryTrigger.allCases {
            #expect(SourceReachability.shouldProbe(on: trigger, sources: away, isReading: false),
                    "\(trigger)")
            #expect(!SourceReachability.shouldProbe(on: trigger, sources: away, isReading: true),
                    "\(trigger)")
        }
    }

    // MARK: - Nothing to reconnect

    @Test("Nothing away is nothing to ask")
    func nothingAwayNoProbe() {
        #expect(!SourceReachability.shouldProbe(
            on: .connectivityRegained, sources: [source(.connected)], isReading: false
        ))
        #expect(!SourceReachability.shouldProbe(
            on: .connectivityRegained, sources: [], isReading: false
        ))
    }

    @Test("A source still connecting is not one that is away")
    func connectingIsNotAway() {
        // `connecting` is not a verdict — the library probes on appearance and a trigger
        // arriving in that window would put a second request per source on the network
        // beside the first.
        #expect(!SourceReachability.shouldProbe(
            on: .connectivityRegained, sources: [source(.connecting)], isReading: false
        ))
    }

    @Test("A refused credential is not retried by a network coming back")
    func unauthorizedIsNotRetried() {
        // No amount of network makes a rejected key work. `sources` gives that state a
        // single action the reader takes, and probing it on every hop would relist it.
        #expect(!SourceReachability.shouldProbe(
            on: .connectivityRegained,
            sources: [source(.unauthorized(reason: "Sign-in needed"))],
            isReading: false
        ))
    }

    @Test("One source away among several is enough to ask")
    func oneAwayIsEnough() {
        let sources = [source(.connected), source(.unreachable(since: moment)), source(.connecting)]

        #expect(SourceReachability.shouldProbe(
            on: .returnedToForeground, sources: sources, isReading: false
        ))
    }

    // MARK: - The reader is left alone

    @Test("No probe is scheduled while a reader is open")
    func readingIsNotInterrupted() {
        // `sources`' *Automatic recovery*: reconnecting "does not present a notification or
        // interrupt reading". This is the whole of that clause — a requirement about *not*
        // doing something, so the assertion is that nothing was scheduled rather than that
        // something eventually was.
        //
        // Both triggers, because both arrive from the system rather than from a view: a
        // dropped Wi-Fi mid-chapter and an app returning to a reader that was already open
        // are the two ways this happens.
        #expect(!SourceReachability.shouldProbe(
            on: .connectivityRegained, sources: away, isReading: true
        ))
        #expect(!SourceReachability.shouldProbe(
            on: .returnedToForeground, sources: away, isReading: true
        ))
    }

    @Test("The reader outranks every other reason to probe")
    func readingOutranksEverything() {
        // Several sources away, both occasions, and still nothing: the guard is not a
        // tiebreak that a long enough outage overrules.
        let sources = [
            source(.unreachable(since: moment)),
            source(.unreachable(since: moment.addingTimeInterval(-86_400))),
            source(.connected),
        ]

        for trigger in RetryTrigger.allCases {
            #expect(!SourceReachability.shouldProbe(on: trigger, sources: sources, isReading: true),
                    "\(trigger)")
        }
    }

    // MARK: - What a monitor's report is worth

    @Test("Only a path appearing where there was none is a regained connection")
    func onlyTheEdgeIsATrigger() {
        #expect(SourceReachability.trigger(hasNetwork: true, previously: false) == .connectivityRegained)
    }

    @Test("A path that was already there is no trigger")
    func steadyPathIsNoTrigger() {
        // A monitor reports every path change: one Wi-Fi network swapped for another, an
        // interface coming up beside the one already carrying traffic, a VPN attaching.
        // Reading each as a regain turns "retries immediately, once" into a probe per hop.
        #expect(SourceReachability.trigger(hasNetwork: true, previously: true) == nil)
    }

    @Test("Losing the network is no trigger at all")
    func losingThePathIsNoTrigger() {
        #expect(SourceReachability.trigger(hasNetwork: false, previously: true) == nil)
        #expect(SourceReachability.trigger(hasNetwork: false, previously: false) == nil)
    }

    // MARK: - The observer over an injected signal

    @Test("A dropped and regained network produces exactly one trigger")
    func oneRegainOneTrigger() async {
        let triggers = await collect(from: [false, true])

        #expect(triggers == [.connectivityRegained])
    }

    @Test("A monitor's opening report is not a regain")
    func openingReportIsNotARegain() {
        // The first thing a monitor says describes the network as it already is rather than
        // a change to it. Read as a regain it would probe every source a moment after the
        // library's own appearance probe already did.
        #expect(SourceReachability.trigger(hasNetwork: true, previously: true) == nil)
    }

    @Test("A flapping network produces one trigger per regain and no more")
    func flappingProducesOnePerRegain() async {
        // Eight reports and two regains: the run of `true` at the front is the network the
        // app started on, and the repeats inside each run are the hops a monitor reports
        // without the reader having been offline at all.
        let triggers = await collect(from: [true, true, false, false, true, true, false, true])

        #expect(triggers == [.connectivityRegained, .connectivityRegained])
    }

    @Test("A signal that never leaves the network alone produces nothing")
    func steadySignalProducesNothing() async {
        #expect(await collect(from: [true, true, true]).isEmpty)
    }

    /// The triggers an injected sequence of path reports produces.
    ///
    /// The signal is handed in, which is the whole point: no `NWPathMonitor`, no network,
    /// and the same list of reports drives Android's mirror of this case.
    private func collect(from reports: [Bool]) async -> [RetryTrigger] {
        let paths = AsyncStream<Bool> { continuation in
            for report in reports { continuation.yield(report) }
            continuation.finish()
        }
        var collected: [RetryTrigger] = []
        for await trigger in SourceReachability.triggers(from: paths) { collected.append(trigger) }
        return collected
    }
}
