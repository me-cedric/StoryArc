public import Foundation

/// A publication identity as the document spells it.
///
/// A shape of its own rather than ``PublicationIdentity`` itself, because the two platforms
/// spell its server half differently — iOS writes `sourceID` and `remoteID`, Android writes
/// `sourceId` and `remoteId`. The document takes the lower-camel `Id`, which is what every
/// other key in it uses.
public struct DocumentIdentity: Sendable, Equatable, Codable {
    public var serverSourceId: UUID?
    public var serverRemoteId: String?
    public var contentDigest: String?
    public var normalizedPath: String?

    public init(
        serverSourceId: UUID? = nil,
        serverRemoteId: String? = nil,
        contentDigest: String? = nil,
        normalizedPath: String? = nil
    ) {
        self.serverSourceId = serverSourceId
        self.serverRemoteId = serverRemoteId
        self.contentDigest = contentDigest
        self.normalizedPath = normalizedPath
    }

    public init(_ identity: PublicationIdentity) {
        self.init(
            serverSourceId: identity.serverIdentifier?.sourceID,
            serverRemoteId: identity.serverIdentifier?.remoteID,
            contentDigest: identity.contentDigest,
            normalizedPath: identity.normalizedPath
        )
    }

    /// The identity this one names.
    ///
    /// A server half needs both of its components, so a document carrying only one of them
    /// is read as having no server half at all. A guessed server identity would file two
    /// different publications as one, which is the loss `PublicationIdentity` exists to
    /// prevent.
    public var identity: PublicationIdentity {
        let server: PublicationIdentity.ServerIdentifier? =
            if let sourceID = serverSourceId, let remoteID = serverRemoteId {
                PublicationIdentity.ServerIdentifier(sourceID: sourceID, remoteID: remoteID)
            } else {
                nil
            }
        return PublicationIdentity(
            serverIdentifier: server,
            contentDigest: contentDigest,
            normalizedPath: normalizedPath
        )
    }
}

/// A reading position as the document spells it: a named kind and named fields.
///
/// design.md's table, fourth row. iOS stores a position as one JSON blob and Android as nine
/// flat columns in a Room table, and neither shape is a thing a reader can read or a later
/// version can diff. The named fields are the agreed shape, and each platform converts.
///
/// **Times are whole milliseconds.** iOS keeps a listening offset as seconds in a `Double`
/// and Android as millis in a `Long`. Millis is the one of the two that is exact, and a
/// listening position has no use for a finer unit than a millisecond.
public enum DocumentPosition: Sendable, Equatable, Codable {
    case page(index: Int, of: Int)
    case reflowable(progression: Double, locator: String)
    case listening(part: Int, partCount: Int, offsetMillis: Int64, ofMillis: Int64?)

    public init(_ position: ReadingPosition) {
        switch position {
        case let .page(index, total):
            self = .page(index: index, of: total)
        case let .reflowable(progression, locator):
            self = .reflowable(progression: progression, locator: locator)
        case let .listening(part, partCount, offset, total):
            self = .listening(
                part: part,
                partCount: partCount,
                offsetMillis: Self.millis(offset),
                ofMillis: total.map(Self.millis)
            )
        }
    }

    public var position: ReadingPosition {
        switch self {
        case let .page(index, total):
            .page(index: index, of: total)
        case let .reflowable(progression, locator):
            .reflowable(progression: progression, locator: locator)
        case let .listening(part, partCount, offset, total):
            .listening(
                part: part,
                partCount: partCount,
                offset: Self.seconds(offset),
                of: total.map(Self.seconds)
            )
        }
    }

    private static func millis(_ seconds: TimeInterval) -> Int64 {
        Int64((seconds * 1000).rounded())
    }

    private static func seconds(_ millis: Int64) -> TimeInterval {
        TimeInterval(millis) / 1000
    }

    private enum Kind: String, Codable {
        case page
        case reflowable
        case listening
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case index
        case of
        case progression
        case locator
        case part
        case partCount
        case offsetMillis
        case ofMillis
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .page:
            self = .page(
                index: try container.decode(Int.self, forKey: .index),
                of: try container.decode(Int.self, forKey: .of)
            )
        case .reflowable:
            self = .reflowable(
                progression: try container.decode(Double.self, forKey: .progression),
                locator: try container.decodeIfPresent(String.self, forKey: .locator) ?? ""
            )
        case .listening:
            self = .listening(
                part: try container.decode(Int.self, forKey: .part),
                partCount: try container.decode(Int.self, forKey: .partCount),
                offsetMillis: try container.decode(Int64.self, forKey: .offsetMillis),
                ofMillis: try container.decodeIfPresent(Int64.self, forKey: .ofMillis)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .page(index, total):
            try container.encode(Kind.page, forKey: .kind)
            try container.encode(index, forKey: .index)
            try container.encode(total, forKey: .of)
        case let .reflowable(progression, locator):
            try container.encode(Kind.reflowable, forKey: .kind)
            try container.encode(progression, forKey: .progression)
            try container.encode(locator, forKey: .locator)
        case let .listening(part, partCount, offset, total):
            try container.encode(Kind.listening, forKey: .kind)
            try container.encode(part, forKey: .part)
            try container.encode(partCount, forKey: .partCount)
            try container.encode(offset, forKey: .offsetMillis)
            try container.encodeIfPresent(total, forKey: .ofMillis)
        }
    }
}
