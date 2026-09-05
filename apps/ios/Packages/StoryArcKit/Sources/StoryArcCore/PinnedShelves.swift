public import Foundation

/// Which shelf a reader has pinned to the home surface.
///
/// A collection and a reading list are deliberately different types — `Shelves.swift` says
/// why at length — so a pin has to name which kind it is. Two UUIDs colliding across the two
/// is not a thing that happens, and a pin that silently followed the wrong one would be a
/// bug nobody could reproduce.
public enum ShelfPin: Sendable, Hashable, Codable {
    case collection(UUID)
    case list(UUID)

    /// The token this pin is written down as.
    ///
    /// A string rather than the `Codable` synthesis, because these are stored in the same
    /// preferences both platforms already use for scalars, and a string set is what both
    /// have. `collection:` and `list:` rather than `0:`/`1:` so a stored value can be read
    /// by a person looking at a preferences file, and so reordering the cases cannot
    /// silently repoint every pin a reader has.
    public var token: String {
        switch self {
        case let .collection(id): "collection:\(id.uuidString)"
        case let .list(id): "list:\(id.uuidString)"
        }
    }

    /// A token read back, or `nil` for anything this version does not understand.
    ///
    /// `nil` rather than a guess. An unreadable pin drops one shelf off the home surface,
    /// which the reader can see and put back; a guessed one pins a shelf they never chose
    /// and gives them nothing to undo.
    public init?(token: String) {
        let parts = token.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
        switch parts[0] {
        case "collection": self = .collection(id)
        case "list": self = .list(id)
        default: return nil
        }
    }
}

/// The shelves a reader has asked to see on the home surface, and the order that puts them in.
///
/// `home-screen`, *Pinned shelves*: a pinned collection or reading list "appears on the home
/// surface as a shelf of its own, ahead of the unpinned ones", and "unpinning it removes the
/// shelf without altering the collection or the list".
///
/// **That second clause is why this is a set of keys beside the shelves rather than a flag on
/// them.** A `isPinned` field on ``PublicationCollection`` and ``ReadingList`` would have to
/// survive a server pull, which rewrites a server-backed shelf wholesale — so pinning a
/// Kavita reading list and then syncing would either lose the pin or make the pull's
/// overwrite conditional, and a shelf's own record would carry a fact about the home screen.
/// Held apart, unpinning cannot alter a collection because it never touches one.
public struct PinnedShelves: Sendable, Equatable {
    private var pins: Set<ShelfPin>

    public init(_ pins: Set<ShelfPin> = []) {
        self.pins = pins
    }

    /// Read back from stored tokens, dropping any this version cannot parse.
    public init(tokens: [String]) {
        self.pins = Set(tokens.compactMap(ShelfPin.init(token:)))
    }

    /// What to write down. Sorted, so two runs that pinned the same shelves produce the same
    /// stored value and a diff of a preferences file is readable.
    public var tokens: [String] { pins.map(\.token).sorted() }

    public var isEmpty: Bool { pins.isEmpty }

    public func contains(_ pin: ShelfPin) -> Bool { pins.contains(pin) }

    /// Pinned if it was not, unpinned if it was. One action either way, because the control
    /// is one control.
    public func toggling(_ pin: ShelfPin) -> PinnedShelves {
        var next = pins
        if next.contains(pin) { next.remove(pin) } else { next.insert(pin) }
        return PinnedShelves(next)
    }

    /// The same shelves, pinned ones first.
    ///
    /// **Stable within each group**, which is the part worth stating: the reader's own order
    /// survives inside the pinned run and inside the unpinned one, so pinning a shelf moves
    /// it to the front and moves nothing else. A sort would have been shorter and would have
    /// reshuffled everything the first time two shelves compared equal.
    ///
    /// Generic over the element so a collection and a reading list are ordered by one rule
    /// asked twice, rather than by two rules that can disagree.
    public func ordering<Shelf>(_ shelves: [Shelf], by pin: (Shelf) -> ShelfPin) -> [Shelf] {
        let pinned = shelves.filter { pins.contains(pin($0)) }
        let rest = shelves.filter { !pins.contains(pin($0)) }
        return pinned + rest
    }

    /// Where the choice is written down. Its own key, in the same `UserDefaults` everything
    /// else on this screen uses, so nothing has to be migrated to add it.
    public static let storageKey = "app.storyarc.pinnedShelves"

    /// The whole set as one scalar, because `@AppStorage` stores scalars.
    ///
    /// Space-separated: a token is a word and a UUID, neither of which can contain a space,
    /// so the separator cannot appear inside a value. Android stores the same tokens as a
    /// `Set<String>`, which its preferences take natively — the container differs and the
    /// tokens do not, which is the half that has to match.
    public var stored: String { tokens.joined(separator: " ") }

    public init(stored: String) {
        self.init(tokens: stored.split(separator: " ").map(String.init))
    }
}
