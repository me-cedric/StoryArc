public import Foundation

/// How StoryArc decides two things are the same publication.
///
/// ADR-0006: a server identifier wins when the publication came from a source
/// that has one; otherwise a content digest, which survives renames, moves and
/// re-downloads; a normalised path only as a last resort.
///
/// Both a server id and a content digest are recorded when both are known —
/// that is what lets a file read from a folder and the same file read from a
/// Kavita server resolve to one progress record.
public struct PublicationIdentity: Sendable, Hashable, Codable {
    public let serverIdentifier: ServerIdentifier?
    public let contentDigest: String?
    public let normalizedPath: String?

    /// A stable key for lists, diffing and anything stored against a publication.
    ///
    /// Built from whichever components exist, in the priority ADR-0006 gives them, so
    /// a publication that later gains a server id keeps a usable key throughout
    /// rather than changing identity mid-session.
    ///
    /// On the identity rather than on ``Publication``, because the identity is the
    /// only thing that decides it — and a caller that holds an identity and not a
    /// whole publication needs it just as much.
    public var stableID: String {
        if let server = serverIdentifier {
            return "srv:\(server.sourceID.uuidString):\(server.remoteID)"
        }
        if let digest = contentDigest { return "sha:\(digest)" }
        return "path:\(normalizedPath ?? "")"
    }

    public struct ServerIdentifier: Sendable, Hashable, Codable {
        public let sourceID: UUID
        public let remoteID: String

        public init(sourceID: UUID, remoteID: String) {
            self.sourceID = sourceID
            self.remoteID = remoteID
        }
    }

    public init(
        serverIdentifier: ServerIdentifier? = nil,
        contentDigest: String? = nil,
        normalizedPath: String? = nil
    ) {
        self.serverIdentifier = serverIdentifier
        self.contentDigest = contentDigest
        self.normalizedPath = normalizedPath
    }

    /// Two identities match when *any* recorded component matches. A file that
    /// gains a server id later still resolves to the progress recorded against
    /// its digest.
    public func matches(_ other: PublicationIdentity) -> Bool {
        if let mine = serverIdentifier, let theirs = other.serverIdentifier, mine == theirs {
            return true
        }
        if let mine = contentDigest, let theirs = other.contentDigest, mine == theirs {
            return true
        }
        if let mine = normalizedPath, let theirs = other.normalizedPath, mine == theirs {
            return true
        }
        return false
    }

    /// True when nothing at all was recorded — a bug at the call site rather
    /// than a state the app should tolerate.
    public var isEmpty: Bool {
        serverIdentifier == nil && contentDigest == nil && normalizedPath == nil
    }
}
