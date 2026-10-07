import Foundation
import Testing

@testable import LibraryFeature

import Smb
import StoryArcCore

/// A probe of a share keeps what its session negotiated, for the source detail screen.
///
/// `network-share`'s *Encrypted transport*: the screen states whether the connection is
/// encrypted. It reads ``StoryArcCore/ShareSessions``, and the probe is what writes there.
/// Against the two fixture servers, so the value is the one the wire gave:
/// `scripts/smb-server.sh` on 4445 offers encryption, `scripts/smb-server.sh --encrypted` on
/// 4446 demands it. Each case is skipped when its server is not running. Android's
/// `ShareSessionRecordTest` is the mirror.
@MainActor
@Suite("A share probe keeps its session's transport", .serialized)
struct ShareProbeRecordTests {

    @Test("A probe keeps an encrypted SMB 3.1.1 session", arguments: [4445, 4446])
    func keepsTheSession(port: Int) async throws {
        guard Self.isListening(port: port) else { return }
        let source = UUID()
        let address = SmbAddress(
            host: "127.0.0.1",
            share: "Comics",
            username: NSUserName(),
            password: "lovelace",
            port: port
        )

        try await ShareProbe.reach(source, at: address)

        #expect(
            ShareSessions.shared.negotiated[source]
                == ShareTransport(dialect: "SMB 3.1.1", isEncrypted: true)
        )
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
