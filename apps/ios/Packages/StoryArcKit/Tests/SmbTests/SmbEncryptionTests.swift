import Foundation
import Testing

@testable import Smb

/// A share that demands SMB 3 encryption is reached, sealed, and says so.
///
/// `network-share`'s *Encrypted transport*: "WHEN the server supports SMB 3 encryption THEN
/// the app negotiates it AND the source detail screen states whether the connection is
/// encrypted". The vendored client used to offer SMB 2.0.2 and 2.1 only, so this share
/// refused it at the session setup. ADR-0018.
///
/// `scripts/smb-server.sh --encrypted` serves the fixture corpus with `smb encrypt =
/// required` on port 4446. Skipped when it is not running.
@Suite("SMB 3 encryption", .serialized)
struct SmbEncryptionTests {
    private static func address(port: Int) -> SmbAddress {
        SmbAddress(
            host: "127.0.0.1",
            share: "Comics",
            username: NSUserName(),
            password: "lovelace",
            port: port
        )
    }

    private let encrypted = Self.address(port: 4446)

    @Test("A share that demands encryption gets a sealed SMB 3.1.1 session")
    func negotiatesEncryption() async throws {
        try await withServer(encrypted) {
            let identity = try await SmbClient(address: encrypted).connect()
            #expect(identity.dialect == "SMB 3.1.1")
            #expect(identity.isEncrypted)
        }
    }

    @Test("A sealed session lists the share and reads part of a file")
    func listsAndReads() async throws {
        try await withServer(encrypted) {
            let client = SmbClient(address: encrypted)
            let entries = try await client.list()
            #expect(entries.contains { $0.name == "Quiet Machines.cbz" })

            let source = try await client.open("Quiet Machines.cbz")
            let head = try await source.read(offset: 0, count: 2)
            #expect(Array(head) == Array("PK".utf8))
            // The last bytes too, so a read that spans more than one transform is covered.
            let tail = try await source.read(offset: source.length - 22, count: 22)
            #expect(tail.count == 22)
        }
    }

    @Test("A share that only offers encryption is sealed as well")
    func encryptsWhereOffered() async throws {
        let offered = Self.address(port: 4445)
        try await withServer(offered) {
            let identity = try await SmbClient(address: offered).connect()
            #expect(identity.dialect == "SMB 3.1.1")
            #expect(identity.isEncrypted)
        }
    }

    /// Runs the body only when the fixture server is there.
    private func withServer(_ address: SmbAddress, _ body: () async throws -> Void) async throws {
        guard Self.isListening(port: UInt16(address.port)) else { return }
        try await body()
    }

    /// A TCP connect only, so a missing server skips the test rather than failing it.
    private static func isListening(port: UInt16) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
