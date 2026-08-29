import Foundation
import Testing

@testable import StoryArcCore

/// The two decisions in probing a source: how long to wait, and what the answer means.
///
/// Android's `SourceProbeTest` asserts the same table, case for case.
@Suite("Source probe")
struct SourceProbeTests {

    private let moment = Date(timeIntervalSince1970: 1_000)

    @Test("The backoff doubles from five seconds")
    func backoffDoubles() {
        #expect(SourceProbe.delay(afterFailures: 1) == 5)
        #expect(SourceProbe.delay(afterFailures: 2) == 10)
        #expect(SourceProbe.delay(afterFailures: 3) == 20)
        #expect(SourceProbe.delay(afterFailures: 4) == 40)
    }

    @Test("The backoff stops at five minutes, however long a source has been away")
    func backoffCaps() {
        #expect(SourceProbe.delay(afterFailures: 7) == 300)
        #expect(SourceProbe.delay(afterFailures: 50) == 300)
        // A day of failures must not overflow into a wait nobody comes back from.
        #expect(SourceProbe.delay(afterFailures: 100_000) == 300)
    }

    @Test("No failures is not a wait at all")
    func noFailuresNoWait() {
        #expect(SourceProbe.delay(afterFailures: 0) == 0)
        #expect(SourceProbe.delay(afterFailures: -1) == 0)
    }

    @Test("A success connects")
    func successConnects() {
        #expect(SourceProbe.state(forStatus: 200, at: moment, reason: "x") == .connected)
        #expect(SourceProbe.state(forStatus: 204, at: moment, reason: "x") == .connected)
    }

    @Test("A refused credential is the one state that asks the reader to act")
    func refusedIsUnauthorized() {
        let state = SourceProbe.state(forStatus: 401, at: moment, reason: "Sign-in needed")

        #expect(state == .unauthorized(reason: "Sign-in needed"))
        #expect(state.needsUserAction)
    }

    @Test("Anything else is unreachable, and asks nothing of the reader")
    func othersAreUnreachable() {
        for code in [404, 500, 502, 0] {
            let state = SourceProbe.state(forStatus: code, at: moment, reason: "x")
            #expect(state == .unreachable(since: moment), "status \(code)")
            // "Offline is a normal state, not an error" — a grey indicator, never a red one.
            #expect(!state.needsUserAction, "status \(code)")
        }
    }

    @Test("A connection that never answered reads the same as a bad one")
    func failureIsUnreachable() {
        #expect(SourceProbe.state(forFailureAt: moment) == .unreachable(since: moment))
    }

    @Test("Only a source that can be away is asked")
    func onlyRemoteSourcesAreProbed() {
        #expect(!SourceProbe.isRemote(.localFolder))
        #expect(SourceProbe.isRemote(.networkShare))
        #expect(SourceProbe.isRemote(.opdsCatalog))
        #expect(SourceProbe.isRemote(.kavitaServer))
    }
}
