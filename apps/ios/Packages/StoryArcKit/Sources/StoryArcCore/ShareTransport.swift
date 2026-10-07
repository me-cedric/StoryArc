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

/// The last session each network-share source negotiated, since the app started.
///
/// Kept in memory only. A transport describes a connection, and a value read from disk is a
/// claim about a connection that no longer exists — the same argument that keeps a source's
/// connection state off disk. Every probe of a share records here, and the source detail
/// screen reads it through ``SourceDiagnosis/transport``. Observable, so the sentence follows
/// a test of the connection the moment it ends.
@MainActor
@Observable
public final class ShareSessions {
    public static let shared = ShareSessions()

    /// Every source's last session, keyed by the source's id.
    public private(set) var negotiated: [UUID: ShareTransport] = [:]

    public init() {}

    /// Records what the newest session with `sourceID` negotiated.
    public func record(_ transport: ShareTransport, for sourceID: UUID) {
        negotiated[sourceID] = transport
    }
}
