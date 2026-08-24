public import Foundation

/// Where publications come from. See `docs/openspec/specs/sources`.
public enum SourceKind: String, Sendable, Codable, CaseIterable {
    case localFolder
    case networkShare
    case opdsCatalog
    case kavitaServer
}

/// `sources` requires exactly these four states, and requires that none of them
/// prevents browsing what is already cached.
public enum SourceConnectionState: Sendable, Equatable {
    case connected
    case connecting
    case unreachable(since: Date)
    case unauthorized(reason: String)

    /// Whether the source can serve content that is not already downloaded.
    public var canFetch: Bool { self == .connected }

    /// Offline is a normal state, not a failure — `status/offline` is grey, and
    /// only `unauthorized` is something the user must act on.
    public var needsUserAction: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

public struct Source: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var displayName: String
    public let kind: SourceKind
    public var state: SourceConnectionState
    public var lastSuccessfulSync: Date?

    /// Opaque handle into the platform secure store. Never the secret itself —
    /// `sources` forbids a secret reaching preferences, logs or backups.
    public var credentialReference: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        kind: SourceKind,
        state: SourceConnectionState = .connecting,
        lastSuccessfulSync: Date? = nil,
        credentialReference: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.state = state
        self.lastSuccessfulSync = lastSuccessfulSync
        self.credentialReference = credentialReference
    }
}

/// Exponential backoff for an unreachable source: start at 5 s, cap at 5 min.
public enum ReconnectBackoff {
    public static let initialDelay: Duration = .seconds(5)
    public static let maximumDelay: Duration = .seconds(300)

    public static func delay(forAttempt attempt: Int) -> Duration {
        guard attempt > 0 else { return initialDelay }
        let seconds = min(5.0 * pow(2.0, Double(attempt - 1)), 300.0)
        return .seconds(seconds)
    }
}
