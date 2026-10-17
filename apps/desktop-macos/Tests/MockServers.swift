import Darwin
import Foundation

/// The repository's mock servers, as a walk finds them.
///
/// `pnpm opds`, `pnpm kavita` and `pnpm smb` (or `scripts/smb-server.sh --encrypted`) serve
/// the corpus on 4444, 5000, 4445 and 4446 by default; the scripts say so at the top. A walk
/// reads each port from the environment first, so a run beside another lane's servers can
/// move them: `TEST_RUNNER_STORYARC_OPDS_PORT=4644` in front of the test command reaches
/// the test process as `STORYARC_OPDS_PORT`. A server that is not listening skips its walk
/// with that reason rather than failing it: the walks need a server someone started.
enum MockServers {
    static var opdsPort: Int { port("STORYARC_OPDS_PORT", default: 4444) }
    static var kavitaPort: Int { port("STORYARC_KAVITA_PORT", default: 5000) }
    static var smbPort: Int { port("STORYARC_SMB_PORT", default: 4445) }
    static var encryptedSmbPort: Int { port("STORYARC_SMB_ENCRYPTED_PORT", default: 4446) }
    /// The egress collector of `apps/desktop-web/epub/test/collector.mjs` (`pnpm egress` from
    /// that directory). Out of process because the sandboxed app may not listen on a socket:
    /// it has `network.client` and no server entitlement, and `EntitlementsTests` keeps it so.
    static var egressPort: Int { port("STORYARC_EGRESS_PORT", default: 4815) }

    /// The share's user. `scripts/smb-server.sh` signs in as the Mac's own user; the container
    /// image of the same configuration signs in as `reader`.
    static var smbUser: String { ProcessInfo.processInfo.environment["STORYARC_SMB_USER"] ?? NSUserName() }
    static let smbPassword = "lovelace"
    static let smbShare = "Comics"

    static let opdsUser = "ada"
    static let opdsPassword = "lovelace"
    static let kavitaKey = "storyarc-test-key"

    static var opdsRoot: String { "http://127.0.0.1:\(opdsPort)/opds/all" }
    static var opdsPrivate: String { "http://127.0.0.1:\(opdsPort)/private" }
    static var kavitaBase: String { "http://127.0.0.1:\(kavitaPort)" }

    static var isOpdsUp: Bool { isListening(opdsPort) }
    static var isKavitaUp: Bool { isListening(kavitaPort) }
    static var isSmbUp: Bool { isListening(smbPort) }
    static var isEncryptedSmbUp: Bool { isListening(encryptedSmbPort) }
    static var egressOrigin: String { "http://127.0.0.1:\(egressPort)" }
    static var isEgressUp: Bool { isListening(egressPort) }

    private static func port(_ name: String, default value: Int) -> Int {
        ProcessInfo.processInfo.environment[name].flatMap(Int.init) ?? value
    }

    /// Whether something accepts a connection on the loopback at `port`. A closed port on the
    /// loopback refuses at once, so this does not wait.
    static func isListening(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
