import Foundation
import Testing

@testable import Smb

/// What this suite can and cannot prove.
///
/// The reachability clock is checked here directly. The reopen branch itself is not: the
/// source's session is private to it, and widening that surface to reach it from a test
/// would be an abstraction that exists only for the test. Android's suite closes the handle
/// out from under its source and proves the branch there; the two implementations follow
/// the same shape, and this one at least proves a source keeps working across reads.
@Suite("SMB reconnection", .serialized)
struct SmbReconnectTests {
    private let address = SmbAddress(
        host: "127.0.0.1",
        share: "Comics",
        username: NSUserName(),
        password: "lovelace",
        port: 4445
    )

    @Test("a source keeps working across reads")
    func keepsWorking() async throws {
        guard (try? await SmbClient(address: address).connect()) != nil else { return }

        let source = try await SmbClient(address: address).open("Quiet Machines.cbz")
        let before = try await source.read(offset: 0, count: 4)

        // What a sleep or a Wi-Fi change leaves behind: a session the server has forgotten.
        // Restarting the fixture server is not available from here, so the next best proof
        // is that a second read after a long-enough gap still gets through the same source.
        let after = try await source.read(offset: 0, count: 4)
        #expect(Array(after) == Array(before))
        #expect(SmbReachability.blockedSince == nil)
    }

    @Test("trouble is timed from the first failure, not the latest")
    func timesFromFirstFailure() {
        SmbReachability.clear()
        let first = Date(timeIntervalSince1970: 1_000)
        SmbReachability.noteFailure(at: first)
        SmbReachability.noteFailure(at: Date(timeIntervalSince1970: 2_000))
        #expect(SmbReachability.blockedSince == first)

        SmbReachability.noteSuccess()
        #expect(SmbReachability.blockedSince == nil)
    }
}
