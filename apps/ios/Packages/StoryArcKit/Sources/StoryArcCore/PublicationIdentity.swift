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
