public import Foundation
public import Observation

/// What one session with a network share negotiated.
///
/// `network-share`'s *Encrypted transport* requires the source detail screen to state whether
/// the connection is encrypted. That sentence must follow a measured value, and the value
/// belongs to a session, not to the app: the client encrypts a session only when the server
/// agreed SMB 3 with a cipher in common, so two shares can give two answers. ADR-0019.
///
/// Android's `ShareTransport` is the mirror of this type.
public struct ShareTransport: Sendable, Equatable {
    /// The dialect the two ends agreed, such as `SMB 3.1.1`.
    public let dialect: String
    /// Whether every message of the session is encrypted.
    public let isEncrypted: Bool

    public init(dialect: String, isEncrypted: Bool) {
        self.dialect = dialect
        self.isEncrypted = isEncrypted
    }
}

/// Which share a session was with: the host, the port and the share, and nothing else.
///
/// The session belongs to the server, not to the source row. An add sheet that is still
/// choosing a folder has no source yet, and the library scan and the reader connect from places
/// that never held the source's id. A key every client can build from the address it
/// connects to lets each of them record, and lets the detail screen of any source on that share
/// read the answer. Host and share are compared without regard to case, as SMB does.
public struct ShareKey: Hashable, Sendable {
    private let value: String

    public init(host: String, port: Int, share: String) {
        value = "\(host.lowercased()):\(port)/\(share.lowercased())"
    }

    /// The key of a saved share's locator, `smb://[user@]host[:port]/share[/path]`, or `nil`
    /// when the text is not one.
    public init?(locator: String) {
        guard locator.hasPrefix("smb://") else { return nil }
        let body = locator.dropFirst("smb://".count)
        let parts = body.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let share = parts[1].split(separator: "/").first else { return nil }
        let authority = parts[0].split(separator: "@", omittingEmptySubsequences: false).last ?? ""
        let hostAndPort = authority.split(separator: ":", omittingEmptySubsequences: false)
        guard let host = hostAndPort.first, !host.isEmpty else { return nil }
        let port = hostAndPort.count > 1 ? Int(hostAndPort[1]) : 445
        guard let port else { return nil }
        self.init(host: String(host), port: port, share: String(share))
    }
}

/// The last session each network share negotiated, since the app started.
///
/// Kept in memory only. A transport describes a connection, and a value read from disk is a
/// claim about a connection that no longer exists — the same argument that keeps a source's
/// connection state off disk. Every client that connects records here, whichever screen it
/// serves, and the source detail screen reads it through ``SourceDiagnosis/transport``.
/// Observable, so the sentence follows a connection the moment it ends.
@MainActor
@Observable
public final class ShareSessions {
    public static let shared = ShareSessions()

    /// Every share's last session.
    public private(set) var negotiated: [ShareKey: ShareTransport] = [:]

    public init() {}

    /// Records what the newest session with `share` negotiated.
    public func record(_ transport: ShareTransport, for share: ShareKey) {
        negotiated[share] = transport
    }

    /// Drops what is known of `share`, so the next connection is the one that answers.
    public func forget(_ share: ShareKey) {
        negotiated.removeValue(forKey: share)
    }

    /// What the last session with the share a source's locator names negotiated, if any.
    public func transport(forLocator locator: String?) -> ShareTransport? {
        locator.flatMap(ShareKey.init(locator:)).flatMap { negotiated[$0] }
    }
}
