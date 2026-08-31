public import Foundation

/// Where publications come from. See `docs/openspec/specs/sources`.
public enum SourceKind: String, Sendable, Codable, CaseIterable {
    case localFolder
    case networkShare
    case opdsCatalog
    case kavitaServer

    /// Whether this is a place a reader travels *to*, rather than a shelf already
    /// folded into the library.
    ///
    /// A local folder's publications are scanned and land in the grid, so a way in to
    /// it would lead back to where the reader already is. The other three hold content
    /// that is not on the device and each needs its own browser.
    ///
    /// One property rather than the same three-way comparison in the catalogue strip,
    /// the sidebar and Android's screen: three copies is how one of them ends up wrong.
    /// A `switch` rather than `!= .localFolder` so a fifth kind cannot be quietly
    /// assumed to be browsable — it has to be answered here.
    public var isBrowsable: Bool {
        switch self {
        case .localFolder: false
        case .networkShare, .opdsCatalog, .kavitaServer: true
        }
    }

    /// Whether a reading position recorded here can also be held by the source itself.
    ///
    /// `reading-progress`' *Source cannot store progress* asks the source detail screen to
    /// state that progress "does not sync" when the source has no mechanism for it, and
    /// three of these four have none: a folder and an SMB share are files on a disk, and
    /// OPDS is a catalogue format with no notion of a read position. Kavita is the one with
    /// both halves of a mechanism — `KavitaClient.report(_:)` posts a position to
    /// `Reader/progress` and `continuePoint(ofSeries:)` reads one back, with `KavitaSync`
    /// driving the two. ADR-0006 chose a local-authoritative store over a remote one for
    /// exactly this asymmetry: "most sources cannot store progress at all".
    ///
    /// A property here rather than a comparison in each app's detail screen, for the reason
    /// ``isBrowsable`` gives above: two copies of the same four-way answer is how one of
    /// them ends up wrong. Android's `SourceKind.syncsReadingProgress` answers the same four
    /// the same way.
    public var syncsReadingProgress: Bool {
        switch self {
        case .localFolder, .networkShare, .opdsCatalog: false
        case .kavitaServer: true
        }
    }
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

    /// Where this source points, as the platform names it.
    ///
    /// A folder's path or bookmark name; a server's URL when one exists. The *stable* key:
    /// `displayName` is the reader's and moves when they rename it, so matching a folder to
    /// its source by name means a renamed source is not recognised on the next launch and
    /// gets added a second time. That is the bug this field exists to prevent.
    ///
    /// Optional only so a source can be constructed in a test without inventing one.
    public var locator: String?

    public init(
        id: UUID = UUID(),
        displayName: String,
        kind: SourceKind,
        state: SourceConnectionState = .connecting,
        lastSuccessfulSync: Date? = nil,
        credentialReference: String? = nil,
        locator: String? = nil
    ) {
        self.locator = locator
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
