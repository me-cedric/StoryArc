import Foundation
import Testing

@testable import Smb

/// `library-sync` task 2.2: the sync document written to a share, against a real Samba.
///
/// `scripts/smb-server.sh --writable` serves a writable `Sync` share on 4448, signed.
/// `scripts/smb-server.sh --writable --encrypted` serves the same on 4449 with
/// `smb encrypt = required`. Each case is skipped when its server is not running.
@Suite("SMB sync place", .serialized)
struct SmbSyncPlaceTests {
    private static func address(port: Int) -> SmbAddress {
        SmbAddress(host: "127.0.0.1", share: "Sync", username: NSUserName(), password: "lovelace", port: port)
    }

    /// A name of its own per case, so cases on one share never see each other's file.
    private static func fileName() -> String { "StoryArc Library \(UUID().uuidString).json" }

    @Test("A signed share takes a write, gives it back, and takes an overwrite at that version")
    func signedShareWritesReadsAndOverwrites() async throws {
        try await writesReadsAndOverwrites(port: 4448)
    }

    @Test("An encrypted share takes a write, gives it back, and takes an overwrite at that version")
    func encryptedShareWritesReadsAndOverwrites() async throws {
        try await writesReadsAndOverwrites(port: 4449)
    }

    @Test("A write against a version that changed writes nothing")
    func staleVersionWritesNothing() async throws {
        guard SmbPortProbe.isListening(port: 4448) else { return }
        let place = SmbSyncPlace(address: Self.address(port: 4448))
        let name = Self.fileName()
        #expect(try await place.write(name, data: Data("first".utf8), replacing: nil))
        // Absent was expected, and the file is there.
        #expect(try await !place.write(name, data: Data("second".utf8), replacing: nil))
        #expect(try await !place.write(name, data: Data("second".utf8), replacing: "not-the-version"))
        #expect(try await place.read(name)?.data == Data("first".utf8))
        #expect(try await place.delete(name))
    }

    @Test("A deleted file is gone, reads as none, and leaves no temporary file")
    func deleteRemoves() async throws {
        guard SmbPortProbe.isListening(port: 4448) else { return }
        let place = SmbSyncPlace(address: Self.address(port: 4448))
        let name = Self.fileName()
        #expect(try await place.write(name, data: Data("doomed".utf8), replacing: nil))
        #expect(try await place.names().contains(name))
        #expect(try await place.delete(name))
        #expect(try await place.read(name) == nil)
        let names = try await place.names()
        #expect(!names.contains(name))
        #expect(!names.contains { $0.hasSuffix(".tmp") })
    }

    @Test("A closed place has ended its session, so it holds no connection open")
    func closedPlaceHoldsNoSession() async throws {
        guard SmbPortProbe.isListening(port: 4448) else { return }
        let place = SmbSyncPlace(address: Self.address(port: 4448))
        _ = try await place.names()
        await place.close()
        await #expect(throws: (any Error).self) {
            _ = try await place.names()
        }
    }

    @Test("A share that does not answer is unreachable, not an error")
    func silentShareIsUnreachable() async {
        let place = SmbSyncPlace(address: Self.address(port: 4999))
        await #expect(throws: SmbError.hostUnreachable) {
            _ = try await place.read("StoryArc Library.json")
        }
    }

    private func writesReadsAndOverwrites(port: Int) async throws {
        guard SmbPortProbe.isListening(port: UInt16(port)) else { return }
        let place = SmbSyncPlace(address: Self.address(port: port))
        let name = Self.fileName()
        #expect(try await place.read(name) == nil)
        #expect(try await place.write(name, data: Data("one".utf8), replacing: nil))
        let first = try #require(try await place.read(name))
        #expect(first.data == Data("one".utf8))

        #expect(try await place.write(name, data: Data("two, longer".utf8), replacing: first.version))
        let second = try #require(try await place.read(name))
        #expect(second.data == Data("two, longer".utf8))
        #expect(second.version != first.version)
        #expect(try await place.delete(name))
    }
}

/// A TCP connect only, so a missing server skips a test rather than failing it.
enum SmbPortProbe {
    static func isListening(port: UInt16) -> Bool {
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
