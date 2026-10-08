import Foundation
import Testing

@testable import LibraryFeature

import Smb
import StoryArcCore

/// Every client that connects to a share leaves what its session negotiated, for the source
/// detail screen.
///
/// `network-share`'s *Encrypted transport*: the screen states whether the connection is
/// encrypted, and it reads ``StoryArcCore/ShareSessions``. It used to say "No connection has
/// been made" for a share the app had just read, because only the health probe wrote there; the
/// add sheet, the library scan and the reader connected through other clients and recorded
/// nothing (`close-the-audited-gaps` 23.3). Each path is asserted on its own, so a fourth
/// client that skips the record fails by name rather than by silence.
///
/// Against the two fixture servers, so the value is the one the wire gave:
/// `scripts/smb-server.sh` on 4445 offers encryption, `scripts/smb-server.sh --encrypted` on
/// 4446 demands it. Each case is skipped, and reported as skipped, when its server is not
/// running. Android's `ShareSessionRecordTest` is the mirror.
@MainActor
@Suite("Every client that connects records its session", .serialized)
struct ShareProbeRecordTests {

    private static func address(port: Int, share: String = "Comics") -> SmbAddress {
        SmbAddress(
            host: "127.0.0.1",
            share: share,
            username: NSUserName(),
            password: "lovelace",
            port: port
        )
    }

    private static func key(_ address: SmbAddress) -> ShareKey {
        ShareKey(host: address.host, port: address.port, share: address.share)
    }

    private static let expected = ShareTransport(dialect: "SMB 3.1.1", isEncrypted: true)

    /// The two fixture servers: signed and offering encryption, and demanding it.
    nonisolated static let ports = [4445, 4446]

    @Test(
        "The health probe records",
        .enabled(if: ShareProbeRecordTests.fixturesRunning), arguments: ShareProbeRecordTests.ports
    )
    func probeRecords(port: Int) async throws {
        let target = Self.address(port: port, share: "comics")
        ShareSessions.shared.forget(Self.key(target))
        _ = try await SmbClient(address: target).connect()
        #expect(ShareSessions.shared.negotiated[Self.key(target)] == Self.expected)
    }

    @Test(
        "The add sheet records, before any source exists",
        .enabled(if: ShareProbeRecordTests.fixturesRunning), arguments: ShareProbeRecordTests.ports
    )
    func addSheetRecords(port: Int) async throws {
        // Forgotten first, so a record left by another case cannot answer for this one.
        let sessions = ShareSessions.shared
        let target = Self.address(port: port, share: "COMICS")
        sessions.forget(Self.key(target))
        let connection = SmbConnection()
        connection.host = "\(target.host):\(port)"
        connection.share = "COMICS"
        connection.username = target.username ?? ""
        connection.password = target.password ?? ""

        await connection.connect()

        guard case .browsing = connection.step else {
            Issue.record("The add sheet did not connect: \(connection.step)")
            return
        }
        #expect(sessions.negotiated[Self.key(target)] == Self.expected)
    }

    @Test(
        "The library scan records",
        .enabled(if: ShareProbeRecordTests.fixturesRunning), arguments: ShareProbeRecordTests.ports
    )
    func scanRecords(port: Int) async throws {
        let target = Self.address(port: port, share: "Comics")
        ShareSessions.shared.forget(Self.key(target))
        let page = await SmbContributor.page(
            source: UUID(), client: SmbClient(address: target), address: target, queue: [""]
        )
        #expect(!page.slice.publications.isEmpty, "The scan read nothing, so it never connected.")
        #expect(ShareSessions.shared.negotiated[Self.key(target)] == Self.expected)
    }

    @Test(
        "The reader records",
        .enabled(if: ShareProbeRecordTests.fixturesRunning), arguments: ShareProbeRecordTests.ports
    )
    func readerRecords(port: Int) async throws {
        let target = Self.address(port: port)
        ShareSessions.shared.forget(Self.key(target))
        _ = try await SmbClient(address: target).open("Quiet Machines.cbz")
        #expect(ShareSessions.shared.negotiated[Self.key(target)] == Self.expected)
    }

    @Test("A saved share's locator finds the session its address recorded")
    func locatorFindsTheRecord() async throws {
        let sessions = ShareSessions()
        let target = Self.address(port: 4445)
        sessions.record(Self.expected, for: Self.key(target))

        let locator = SmbLocator.write(
            SmbAddress(host: "127.0.0.1", share: "Comics", path: "Series/Deep", username: "ada", port: 4445)
        )

        #expect(sessions.transport(forLocator: locator) == Self.expected)
        #expect(sessions.transport(forLocator: "smb://127.0.0.1:4446/Comics") == nil)
        #expect(sessions.transport(forLocator: nil) == nil)
    }

    nonisolated static let fixturesRunning = isListening(port: 4445) && isListening(port: 4446)

    nonisolated private static func isListening(port: Int) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
