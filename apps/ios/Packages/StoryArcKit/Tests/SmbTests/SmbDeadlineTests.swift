import Foundation
import Testing

@testable import Smb

/// `SmbDeadline.run` is what keeps a silent SMB read or reopen from waiting forever.
///
/// `network-share`'s *Connection drops while reading*: `SmbSource` used to have no timeout at
/// all, on a read or on a reopen, because `NWConnection.receive` has none of its own. A
/// connection that goes silent waited without end, and the page on screen never failed. This
/// is the mechanism read, tested directly rather than through a share that would have to hang
/// on cue.
@Suite("A read or a reopen fails rather than waiting past its deadline")
struct SmbDeadlineTests {
    private struct Boom: Error, Equatable {}

    @Test("An operation that answers before the deadline succeeds with its own result")
    func fastOperationSucceeds() async throws {
        let result = try await SmbDeadline.run(within: .seconds(5)) { 42 }
        #expect(result == 42)
    }

    @Test("An operation that throws before the deadline rethrows its own error")
    func fastFailurePropagates() async throws {
        await #expect(throws: Boom.self) {
            try await SmbDeadline.run(within: .seconds(5)) { throw Boom() }
        }
    }

    @Test("An operation that never answers fails with hostUnreachable rather than hanging")
    func slowOperationTimesOut() async throws {
        // A deadline short enough that a suite of these does not sit around waiting, and an
        // operation that sleeps for far longer than it — the silent connection this exists
        // for, standing in one line.
        await #expect(throws: SmbError.hostUnreachable) {
            try await SmbDeadline.run(within: .milliseconds(30)) {
                try await Task.sleep(for: .seconds(30))
                return 0
            }
        }
    }

    @Test("An operation that ignores cancellation still loses at the deadline")
    func ignoringCancellationDoesNotHoldTheCaller() async throws {
        // SMBClient's `Connection.send` waits in a continuation with no cancellation handler.
        // A deadline that waits for its losing operation to finish waits exactly as long as
        // the silent connection does, which is the hang this type exists to end.
        let clock = ContinuousClock()
        let started = clock.now
        await #expect(throws: SmbError.hostUnreachable) {
            try await SmbDeadline.run(within: .milliseconds(50)) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) { continuation.resume() }
                }
                return 0
            }
        }
        #expect(clock.now - started < .seconds(1), "the deadline waited for the operation")
    }

    @Test("Losing the race actually stops the slow task rather than leaking it")
    func losingTaskIsCancelled() async throws {
        let flagged = Flag()
        _ = try? await SmbDeadline.run(within: .milliseconds(30)) {
            do {
                try await Task.sleep(for: .seconds(30))
            } catch is CancellationError {
                await flagged.set()
                throw CancellationError()
            }
            return 0
        }
        // The cancellation itself is asynchronous relative to `run` returning, so this gives
        // it a moment rather than asserting on the instant `run` throws.
        for _ in 0..<20 where !(await flagged.value) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await flagged.value, "the losing task was never told to cancel")
    }

    private actor Flag {
        private(set) var value = false
        func set() { value = true }
    }
}
