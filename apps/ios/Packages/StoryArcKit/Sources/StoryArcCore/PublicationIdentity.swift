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
    /// **The path outranks the digest here, and only here.** ``matches(_:)`` keeps
    /// ADR-0006's order — server, then digest, then path — because that order answers
    /// *"are these the same publication?"*, and a digest answers it better than a path
    /// does. This answers a different question: *"what string is this publication
    /// filed under?"* The only requirement of a filing key is that it does not move,
    /// and a key that changes the moment a new component is learned moves for every
    /// publication at once.
    ///
    /// What is filed under it: collection members, reading-list entries, a
    /// `Download`'s id *and the folder its bytes live in*, the chapter-to-publication
    /// table `KavitaProgressStore` keeps, and the library cache's location map.
    /// Re-keying would empty every shelf and orphan every downloaded file on the first
    /// launch after the digest started being computed — a far larger loss than the one
    /// the digest exists to prevent.
    ///
    /// It costs nothing today, because no identity built in production carries both a
    /// path and a digest: the scanners produced a path alone until the digest was
    /// wired in, so ranking a component nothing had cannot re-key anything that
    /// exists. It is a choice about the keys from here on, not a migration.
    ///
    /// A digest-only identity — a file handed over from outside the app, which has no
    /// path this app is entitled to keep — still keys on `sha:`, unchanged.
    ///
    /// On the identity rather than on ``Publication``, because the identity is the
    /// only thing that decides it — and a caller that holds an identity and not a
    /// whole publication needs it just as much.
    public var stableID: String {
        if let server = serverIdentifier {
            return "srv:\(server.sourceID.uuidString):\(server.remoteID)"
        }
        if let path = normalizedPath { return "path:\(path)" }
        if let digest = contentDigest { return "sha:\(digest)" }
        return "path:"
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

    /// The same identity with a content digest recorded against it.
    ///
    /// Components fill in as they become known rather than replacing each other —
    /// ADR-0006 records a server id and a digest together when both are known, and
    /// this is one half of that. A digest already present is kept: whoever supplied it
    /// knew something this caller does not, and a `nil` is the absence of an answer
    /// rather than an answer of "none".
    public func recordingDigest(_ digest: String?) -> PublicationIdentity {
        guard contentDigest == nil, let digest else { return self }
        return PublicationIdentity(
            serverIdentifier: serverIdentifier,
            contentDigest: digest,
            normalizedPath: normalizedPath
        )
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
