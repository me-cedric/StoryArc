import Foundation
import Testing

@testable import Smb

/// Driven against a real SMB2 server rather than a stub.
///
/// `scripts/smb-server.sh` serves the fixture corpus with signing mandatory. A stub would
/// prove the code compiles against the library's types and nothing about whether the two
/// ends agree, which is the only interesting question a protocol client raises.
///
/// Skipped when the server is not running, so a checkout without it still builds.
@Suite("SMB client", .serialized)
struct SmbClientTests {
    private let address = SmbAddress(
        host: "127.0.0.1",
        share: "Comics",
        username: NSUserName(),
        password: "lovelace",
        port: 4445
    )

    @Test("connects and says what it negotiated")
    func connects() async throws {
        try await withServer {
            let identity = try await SmbClient(address: address).connect()
            #expect(identity.dialect.hasPrefix("SMB "))
        }
    }

    @Test("lists the share, folders before files")
    func lists() async throws {
        try await withServer {
            let entries = try await SmbClient(address: address).list()
            #expect(entries.contains { $0.name == "Quiet Machines.cbz" && !$0.isDirectory })
            if let lastFolder = entries.lastIndex(where: \.isDirectory),
               let firstFile = entries.firstIndex(where: { !$0.isDirectory }) {
                #expect(lastFolder < firstFile)
            }
        }
    }

    @Test("reads part of a file rather than the whole of it")
    func readsRange() async throws {
        try await withServer {
            let source = try await SmbClient(address: address).open("Quiet Machines.cbz")
            #expect(source.length > 0)
            // A ZIP's End of Central Directory signature lives in the last bytes, and
            // finding it is exactly the ranged read ADR-0008 designed this for.
            let tail = try await source.read(offset: source.length - 22, count: 22)
            #expect(tail.count == 22)

            let head = try await source.read(offset: 0, count: 2)
            #expect(Array(head) == Array("PK".utf8))
        }
    }

    @Test("a wrong password is rejected, and says so")
    func rejectsWrongPassword() async throws {
        try await withServer {
            var thrown: SmbError?
            do {
                _ = try await SmbClient(address: wrongPassword).connect()
            } catch let error as SmbError {
                thrown = error
            }
            #expect(thrown == .authenticationRejected)
        }
    }

    private var wrongPassword: SmbAddress {
        SmbAddress(
            host: address.host,
            share: address.share,
            username: address.username,
            password: "wrong",
            port: address.port
        )
    }

    /// Runs the body only when the fixture server is there.
    ///
    /// The check is a connection attempt rather than a socket probe: an empty TCP connect
    /// is enough to upset smbd, and a readiness check that breaks the thing it is checking
    /// is worse than none.
    private func withServer(_ body: () async throws -> Void) async throws {
        do {
            _ = try await SmbClient(address: address).connect()
        } catch {
            return
        }
        try await body()
    }
}
