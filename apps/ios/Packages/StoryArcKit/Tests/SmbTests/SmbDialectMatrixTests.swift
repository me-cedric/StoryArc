import Foundation
import Testing

import SMBClient

/// Every SMB 3 path the vendored client added, against a real Samba.
///
/// `SmbEncryptionTests` proves what a reader gets: SMB 3.1.1 with AES-128-GCM, because that
/// is what the client offers first and what Samba picks. This suite forces each of the other
/// paths the client can land on, so that a server which picks differently is not the first
/// test of them:
///
/// - AES-128-CCM, on SMB 3.1.1 and on SMB 3.0.2, where the cipher is implied.
/// - An SMB 3 session with no cipher, which signs with AES-128-CMAC and a derived key.
/// - SMB 2.1, which still signs with HMAC-SHA256 and the session key.
///
/// The share on 4446 demands encryption, so a listing there proves a sealed session. The
/// share on 4445 demands signing, so a listing there proves a signed one. Each test is
/// skipped when its server is not running.
@Suite("SMB 3 dialects and ciphers against Samba", .serialized)
struct SmbDialectMatrixTests {
    private static let sealed = 4446
    private static let signed = 4445

    @Test("SMB 3.1.1 with AES-128-CCM seals the session")
    func ccmOnSMB311() async throws {
        try await expectSession(port: Self.sealed, dialects: [.smb311], ciphers: [.aes128CCM], cipher: .aes128CCM)
    }

    @Test("SMB 3.0.2 seals the session with the AES-128-CCM it implies")
    func ccmOnSMB302() async throws {
        try await expectSession(port: Self.sealed, dialects: [.smb302], ciphers: [.aes128CCM], cipher: .aes128CCM)
    }

    @Test("SMB 3.1.1 with AES-128-GCM seals the session")
    func gcmOnSMB311() async throws {
        try await expectSession(port: Self.sealed, dialects: [.smb311], ciphers: [.aes128GCM], cipher: .aes128GCM)
    }

    @Test("SMB 3.1.1 with no cipher signs with AES-CMAC, and a signing share accepts it")
    func cmacOnSMB311() async throws {
        try await expectSession(port: Self.signed, dialects: [.smb311], ciphers: [], cipher: nil)
    }

    @Test("SMB 3.0.2 with no cipher signs with AES-CMAC, and a signing share accepts it")
    func cmacOnSMB302() async throws {
        try await expectSession(port: Self.signed, dialects: [.smb302], ciphers: [], cipher: nil)
    }

    @Test("SMB 2.1 still signs with HMAC-SHA256, and a signing share accepts it")
    func hmacOnSMB21() async throws {
        try await expectSession(port: Self.signed, dialects: [.smb210], ciphers: [.aes128GCM], cipher: nil)
    }

    @Test("A share that demands encryption refuses SMB 2.1, which cannot encrypt")
    func smb21IsRefusedBySealedShare() async throws {
        guard Self.isListening(port: Self.sealed) else { return }
        let client = SMBClient(host: "127.0.0.1", port: Self.sealed)
        await #expect(throws: (any Error).self) {
            try await client.session.negotiate(dialects: [.smb210])
            try await client.session.sessionSetup(username: NSUserName(), password: "lovelace")
            try await client.connectShare("Comics")
            _ = try await client.listDirectory(path: "")
        }
    }

    private func expectSession(
        port: Int,
        dialects: [Negotiate.Dialects],
        ciphers: [SMB3Cipher],
        cipher expected: SMB3Cipher?
    ) async throws {
        guard Self.isListening(port: port) else { return }
        let client = SMBClient(host: "127.0.0.1", port: port)
        try await client.session.negotiate(dialects: dialects, ciphers: ciphers)
        try await client.session.sessionSetup(username: NSUserName(), password: "lovelace")
        try await client.connectShare("Comics")

        #expect(client.session.dialect == dialects.first)
        #expect(client.session.cipher == expected)
        #expect(client.session.isEncrypting == (expected != nil))

        let files = try await client.listDirectory(path: "")
        #expect(files.contains { $0.name == "Quiet Machines.cbz" })

        let reader = client.fileReader(path: "Quiet Machines.cbz")
        let head = try await reader.read(offset: 0, length: 2)
        #expect(Array(head) == Array("PK".utf8))
        try await reader.close()
    }

    private static func isListening(port: Int) -> Bool {
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
