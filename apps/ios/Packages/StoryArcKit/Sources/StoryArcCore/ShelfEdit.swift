public import Foundation

/// Which server-backed shelf something belongs to.
///
/// A server and one of its shelves, because neither half identifies a shelf on its own: two
/// Kavita servers number their reading lists from one, and a reader may well have both.
public struct ShelfKey: Sendable, Hashable, Codable {
    public let sourceID: String
    public let shelfID: Int

    public init(sourceID: String, shelfID: Int) {
        self.sourceID = sourceID
        self.shelfID = shelfID
    }
}

/// One edit a reader made to a server-backed reading list that the server has not seen.
///
/// `collections-and-reading-lists`: an edit made "while the server is unreachable" is
/// "applied locally, marked pending, and pushed on reconnection". All three need the edit to
/// outlive the moment it was made — the reader who edits on a train has closed the app long
/// before the server is back — so this is a value, written down, not a task in flight.
public struct ShelfEdit: Sendable, Equatable, Codable, Identifiable {
    /// What makes two queued edits the same edit. Adding the same entry to the same list
    /// twice is one pending edit, not two.
    public var id: String { "\(shelf.sourceID)/\(shelf.shelfID)/\(entry)" }

    public let shelf: ShelfKey
    /// The entry it adds, named the way the server names its own entries, so a pull can tell
    /// whether the server has it yet without a second lookup.
    public let entry: String
    /// What to show while it is pending. The server cannot be asked for a title it does not
    /// hold yet, and a row reading "pending" with no name is a row about nothing.
    public let title: String
    public let madeAt: Date

    public init(shelf: ShelfKey, entry: String, title: String, madeAt: Date) {
        self.shelf = shelf
        self.entry = entry
        self.title = title
        self.madeAt = madeAt
    }
}

/// One row of a reading list as the reader sees it.
///
/// Pending or not, because `collections-and-reading-lists` requires "the pending state is
/// visible on the list" — visible on the list itself, not only in a banner above it.
public struct ShelfEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let isPending: Bool

    public init(id: String, title: String, isPending: Bool) {
        self.id = id
        self.title = title
        self.isPending = isPending
    }
}

/// What one server-backed shelf held, the last time it answered.
///
/// Kept so a later answer can be compared against it. Without it "the server changed" is
/// unanswerable, and every refresh is either a conflict or none of them.
public struct ShelfSnapshot: Sendable, Equatable, Codable {
    public let shelf: ShelfKey
    public let entries: [String]

    public init(shelf: ShelfKey, entries: [String]) {
        self.shelf = shelf
        self.entries = entries
    }
}

/// A conflict that has happened and has not yet been said out loud.
///
/// `collections-and-reading-lists`: on a conflict "the user is told once what changed".
/// Once is the hard part, and it is why this is written down rather than raised: a notice
/// that lived in a view model would come back on every refresh, and one that lived nowhere
/// would be lost to the launch that follows the conflict.
public struct ShelfConflictNotice: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let shelf: ShelfKey
    /// What the list is called, so the sentence names it.
    public let shelfName: String
    /// The titles that were dropped, so the sentence says what changed rather than that
    /// something did.
    public let discarded: [String]
    public let at: Date

    public init(shelf: ShelfKey, shelfName: String, discarded: [String], at: Date) {
        id = "\(shelf.sourceID)/\(shelf.shelfID)/\(at.timeIntervalSince1970)"
        self.shelf = shelf
        self.shelfName = shelfName
        self.discarded = discarded
        self.at = at
    }
}

/// Everything owed to a server, everything last seen from one, and everything still to say.
///
/// One value rather than three stores, for the reason ``Shelves`` is one: they are written
/// together in a single reconciliation, and a store that wrote them apart would let an edit
/// outlive the baseline that justifies pushing it.
///
/// Android's `ShelfEditQueue` holds the same three lists and the same operations.
public struct ShelfEditQueue: Sendable, Equatable, Codable {
    public private(set) var edits: [ShelfEdit]
    public private(set) var baselines: [ShelfSnapshot]
    public private(set) var notices: [ShelfConflictNotice]

    public init(
        edits: [ShelfEdit] = [],
        baselines: [ShelfSnapshot] = [],
        notices: [ShelfConflictNotice] = []
    ) {
        self.edits = edits
        self.baselines = baselines
        self.notices = notices
    }

    /// Decodes what is there and defaults what is not, the way ``ShelfSettings`` does: a
    /// queue written by an earlier build must not be dropped because a field arrived.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            edits: try container.decodeIfPresent([ShelfEdit].self, forKey: .edits) ?? [],
            baselines: try container.decodeIfPresent([ShelfSnapshot].self, forKey: .baselines) ?? [],
            notices: try container.decodeIfPresent(
                [ShelfConflictNotice].self,
                forKey: .notices
            ) ?? []
        )
    }

    /// Records an edit, replacing any earlier one for the same entry on the same list.
    public func queueing(_ edit: ShelfEdit) -> ShelfEditQueue {
        ShelfEditQueue(
            edits: edits.filter { $0.id != edit.id } + [edit],
            baselines: baselines,
            notices: notices
        )
    }

    /// Forgets edits the server no longer needs — delivered, or discarded by a conflict.
    public func dropping(_ done: [ShelfEdit]) -> ShelfEditQueue {
        let gone = Set(done.map(\.id))
        return ShelfEditQueue(
            edits: edits.filter { !gone.contains($0.id) },
            baselines: baselines,
            notices: notices
        )
    }

    /// Writes down what a shelf held when it last answered.
    public func recording(_ snapshot: ShelfSnapshot) -> ShelfEditQueue {
        ShelfEditQueue(
            edits: edits,
            baselines: baselines.filter { $0.shelf != snapshot.shelf } + [snapshot],
            notices: notices
        )
    }

    /// What a shelf held when it last answered, or nil for one never seen from this device.
    public func baseline(for shelf: ShelfKey) -> [String]? {
        baselines.first { $0.shelf == shelf }?.entries
    }

    /// The edits still owed for one shelf, oldest first.
    public func pending(for shelf: ShelfKey) -> [ShelfEdit] {
        edits.filter { $0.shelf == shelf }.sorted { $0.madeAt < $1.madeAt }
    }

    /// Keeps a conflict until somebody has said it.
    public func noting(_ notice: ShelfConflictNotice) -> ShelfEditQueue {
        ShelfEditQueue(edits: edits, baselines: baselines, notices: notices + [notice])
    }

    /// Drops a notice that has been shown. This is the "once".
    public func acknowledging(_ id: String) -> ShelfEditQueue {
        ShelfEditQueue(
            edits: edits,
            baselines: baselines,
            notices: notices.filter { $0.id != id }
        )
    }

    /// The oldest thing still to tell the reader, if there is one.
    public var nextNotice: ShelfConflictNotice? {
        notices.min { $0.at < $1.at }
    }

    /// Forgets everything one source defined, for when the source itself is removed.
    public func removingAll(from sourceID: String) -> ShelfEditQueue {
        ShelfEditQueue(
            edits: edits.filter { $0.shelf.sourceID != sourceID },
            baselines: baselines.filter { $0.shelf.sourceID != sourceID },
            notices: notices.filter { $0.shelf.sourceID != sourceID }
        )
    }
}
