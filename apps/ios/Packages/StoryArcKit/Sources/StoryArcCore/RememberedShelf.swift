public import Foundation

/// Which of the two ideas a remembered shelf is.
public enum RememberedShelfKind: String, Sendable, Hashable, CaseIterable {
    /// `collection` and `list` rather than an ordinal, and the same two words ``ShelfPin``
    /// already uses, so one reader of a preferences file learns one vocabulary.
    case collection
    case readingList = "list"
}

/// A shelf a server told the app about, written down so the home surface can name it.
///
/// `home-screen` requires the home surface to be assembled from "local curation alone" and to
/// render "with the same shelves in the same order as when the sources are up". A server's
/// collections and reading lists are fetched once per visit to the shelves screen and were
/// then discarded, so the home surface had no name to draw and could not get one without
/// asking a server — which is the one thing that requirement forbids. `ShelfCard` names that
/// as a gap rather than a decision. This is the memory that closes it.
///
/// **Not a ``PublicationCollection`` with ``ShelfOrigin/server(_:)``.** ``Shelves`` is the
/// reader's own store: `AddToShelfMenu` offers every collection in it as a place to put a
/// publication, `ShelfEditQueue` tracks pending edits against it, and the shelves screen draws
/// all of it as locally owned. A server's shelf put in there would appear in all three and be
/// honoured by none. A record beside it costs one key.
///
/// Mirrors Android's `RememberedShelf`, token for token.
public struct RememberedShelf: Sendable, Hashable, Identifiable {
    public let kind: RememberedShelfKind
    /// The source the shelf came from, which is also how a removed source takes it away.
    public let sourceID: UUID
    /// The server's own numbering for it, which is what opens it again.
    public let serverID: Int
    public let title: String

    public init(kind: RememberedShelfKind, sourceID: UUID, serverID: Int, title: String) {
        self.kind = kind
        self.sourceID = sourceID
        self.serverID = serverID
        self.title = title
    }

    public var id: String { token }

    /// The token this shelf is written down as.
    ///
    /// Modelled on ``ShelfPin/token``: a word and an identity, readable by a person looking at
    /// a preferences file, and immune to a case being reordered. **The title is last**, so a
    /// title holding a colon survives a parse that splits at most three times — and
    /// "Batman: Year One" is the ordinary case rather than the awkward one.
    public var token: String {
        "\(kind.rawValue):\(sourceID.uuidString):\(serverID):\(title)"
    }

    /// A token read back, or `nil` for anything this version cannot read.
    ///
    /// `nil` rather than a guess, for ``ShelfPin/init(token:)``'s reason: a shelf that goes
    /// missing from the home surface reappears the next time the shelves screen asks a server,
    /// where a guessed one would point at whatever the server now numbers that way.
    public init?(token: String) {
        let parts = token.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4,
              let kind = RememberedShelfKind(rawValue: String(parts[0])),
              let sourceID = UUID(uuidString: String(parts[1])),
              let serverID = Int(parts[2]),
              !parts[3].isEmpty
        else { return nil }
        self.init(kind: kind, sourceID: sourceID, serverID: serverID, title: String(parts[3]))
    }

    /// Every shelf a stored record holds, dropping any token this version cannot read.
    public static func shelves(tokens: [String]) -> [RememberedShelf] {
        tokens.compactMap(RememberedShelf.init(token:))
    }

    /// What to write down. Sorted, so two fetches that found the same shelves produce the same
    /// stored value and a diff of a preferences file is readable.
    public static func tokens(_ shelves: [RememberedShelf]) -> [String] {
        shelves.map(\.token).sorted()
    }

    /// Where the record is written down. Its own key, in the same `UserDefaults` the pins use,
    /// so nothing has to be migrated to add it.
    public static let storageKey = "app.storyarc.rememberedShelves"

    /// The whole record as one scalar, because `@AppStorage` stores scalars.
    ///
    /// **Newline-separated, where ``PinnedShelves/stored`` uses a space.** A pin's token is a
    /// word and a UUID and can hold neither; a remembered shelf carries a title, and a title
    /// holds spaces all the time. A title cannot hold a newline: it comes from a server's
    /// single-line field. Android stores the identical tokens as a `Set<String>`, which its
    /// preferences take natively — the container differs and the tokens do not, which is the
    /// half that has to match.
    public static func stored(_ shelves: [RememberedShelf]) -> String {
        tokens(shelves).joined(separator: "\n")
    }

    public static func shelves(stored: String) -> [RememberedShelf] {
        shelves(tokens: stored.split(separator: "\n").map(String.init))
    }
}
