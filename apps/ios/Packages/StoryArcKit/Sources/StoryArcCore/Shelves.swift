public import Foundation

/// Where a grouping came from.
///
/// `collections-and-reading-lists` requires local and server groupings to appear "in one
/// list, each labelled with its source" rather than segregated. A label needs something to
/// label, and this is it.
public enum ShelfOrigin: Sendable, Equatable, Hashable {
    case local
    case server(UUID)

    /// The source it belongs to, if any. `nil` for one the reader made.
    public var sourceID: UUID? {
        if case let .server(id) = self { return id }
        return nil
    }
}

/// An unordered grouping of publications — "Image Comics", "To read with my kid".
///
/// Deliberately not the same type as ``ReadingList``. `collections-and-reading-lists` opens
/// by saying most apps conflate the two and that StoryArc will not, "because ordering is
/// the entire point of one of them". A single type with an `isOrdered` flag is that
/// conflation with an extra field.
public struct PublicationCollection: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String

    /// Publication identities. A set, because a collection has no order and a publication
    /// is either in it or not.
    public var members: Set<String>

    /// The cover the reader chose, when they chose one.
    ///
    /// `nil` means the composite: the spec says a collection's cover "is a composite of its
    /// first four member covers unless the user sets a specific one".
    public var coverMemberID: String?

    public let origin: ShelfOrigin

    public init(
        id: UUID = UUID(),
        name: String,
        members: Set<String> = [],
        coverMemberID: String? = nil,
        origin: ShelfOrigin = .local
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.coverMemberID = coverMemberID
        self.origin = origin
    }
}

/// An ordered sequence where the order carries meaning — a crossover read in publication
/// order, a recommended path through a series.
public struct ReadingList: Sendable, Identifiable, Equatable {
    public let id: UUID
    public var name: String

    /// Publication identities, in the order they are meant to be read. An array, and that
    /// is the whole difference from a collection.
    public var entries: [String]

    public let origin: ShelfOrigin

    public init(
        id: UUID = UUID(),
        name: String,
        entries: [String] = [],
        origin: ShelfOrigin = .local
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.origin = origin
    }

    /// What comes after a publication in this list.
    ///
    /// `collections-and-reading-lists`: when a reader finishes an entry "the next entry in
    /// list order is offered, regardless of series or source". List order, not series
    /// order — that is what a reading list is for.
    public func next(after id: String) -> String? {
        guard let position = entries.firstIndex(of: id), position + 1 < entries.count else {
            return nil
        }
        return entries[position + 1]
    }

    /// What comes before a publication in this list.
    ///
    /// `comic-reader`'s chapter actions run both ways, and a reading list orders its
    /// entries for exactly this — going back through a crossover in the order the reader
    /// arranged it, rather than in whatever order the series numbers fell.
    public func previous(before id: String) -> String? {
        guard let position = entries.firstIndex(of: id), position > 0 else { return nil }
        return entries[position - 1]
    }

    /// How far through the list a reader is.
    ///
    /// Counted as "everything before the first unfinished entry", not "how many are
    /// finished". A reader who skipped ahead and read entry five has not read one to four,
    /// and a list that said five of ten would be telling them they had.
    public func position(finished: (String) -> Bool) -> Int {
        entries.firstIndex { !finished($0) } ?? entries.count
    }
}

/// Every collection and reading list the reader has, and every change that can be made.
///
/// One value type for both, because they are stored together, listed together and edited by
/// the same screens. They stay separate *types* inside it for the reason the spec gives.
public struct Shelves: Sendable, Equatable {
    public private(set) var collections: [PublicationCollection]
    public private(set) var lists: [ReadingList]

    public init(collections: [PublicationCollection] = [], lists: [ReadingList] = []) {
        self.collections = collections
        self.lists = lists
    }

    // MARK: Collections

    public func adding(_ collection: PublicationCollection) -> Shelves {
        guard !collections.contains(where: { $0.id == collection.id }) else { return self }
        return Shelves(collections: collections + [collection], lists: lists)
    }

    /// A blank name is refused rather than stored, for the reason ``SourceRegistry`` refuses
    /// one: every screen that names it would read as if a word were missing.
    public func renaming(collection id: UUID, to name: String) -> Shelves {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        return Shelves(
            collections: collections.map { each in
                guard each.id == id else { return each }
                var renamed = each
                renamed.name = trimmed
                return renamed
            },
            lists: lists
        )
    }

    /// Adds publications to a collection.
    ///
    /// Takes a set, because the spec asks for selection "in bulk from the library" and a
    /// caller adding forty at once should not make forty copies of the collection.
    public func adding(_ members: Set<String>, to id: UUID) -> Shelves {
        Shelves(
            collections: collections.map { each in
                guard each.id == id else { return each }
                var changed = each
                changed.members.formUnion(members)
                return changed
            },
            lists: lists
        )
    }

    public func removing(_ members: Set<String>, from id: UUID) -> Shelves {
        Shelves(
            collections: collections.map { each in
                guard each.id == id else { return each }
                var changed = each
                changed.members.subtract(members)
                // A cover that is no longer a member is no cover. Left alone it would show
                // a book the collection does not contain.
                if let cover = changed.coverMemberID, !changed.members.contains(cover) {
                    changed.coverMemberID = nil
                }
                return changed
            },
            lists: lists
        )
    }

    public func settingCover(_ member: String?, on id: UUID) -> Shelves {
        Shelves(
            collections: collections.map { each in
                guard each.id == id, member == nil || each.members.contains(member ?? "") else {
                    return each
                }
                var changed = each
                changed.coverMemberID = member
                return changed
            },
            lists: lists
        )
    }

    public func deleting(collection id: UUID) -> Shelves {
        Shelves(collections: collections.filter { $0.id != id }, lists: lists)
    }

    // MARK: Reading lists

    public func adding(_ list: ReadingList) -> Shelves {
        guard !lists.contains(where: { $0.id == list.id }) else { return self }
        return Shelves(collections: collections, lists: lists + [list])
    }

    public func renaming(list id: UUID, to name: String) -> Shelves {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        return Shelves(
            collections: collections,
            lists: lists.map { each in
                guard each.id == id else { return each }
                var renamed = each
                renamed.name = trimmed
                return renamed
            }
        )
    }

    /// Appends entries, keeping the order they arrive in and skipping ones already there.
    ///
    /// Ordered, so this takes an array rather than a set: adding three issues of a crossover
    /// in the order the reader picked them is the point.
    public func appending(_ entries: [String], to id: UUID) -> Shelves {
        Shelves(
            collections: collections,
            lists: lists.map { each in
                guard each.id == id else { return each }
                var changed = each
                let known = Set(changed.entries)
                changed.entries += entries.filter { !known.contains($0) }
                return changed
            }
        )
    }

    public func removing(_ entry: String, fromList id: UUID) -> Shelves {
        Shelves(
            collections: collections,
            lists: lists.map { each in
                guard each.id == id else { return each }
                var changed = each
                changed.entries.removeAll { $0 == entry }
                return changed
            }
        )
    }

    /// Moves an entry, taking the destination a drag reports.
    ///
    /// The same convention ``SourceRegistry/moving(_:to:)`` uses, and for the same reason:
    /// removing first and inserting after lands one place early on every downward drag.
    public func moving(_ entry: String, to destination: Int, inList id: UUID) -> Shelves {
        Shelves(
            collections: collections,
            lists: lists.map { each in
                guard each.id == id, let from = each.entries.firstIndex(of: entry) else {
                    return each
                }
                var changed = each
                changed.entries.remove(at: from)
                let to = min(
                    max(destination > from ? destination - 1 : destination, 0),
                    changed.entries.count
                )
                changed.entries.insert(entry, at: to)
                return changed
            }
        )
    }

    public func deleting(list id: UUID) -> Shelves {
        Shelves(collections: collections, lists: lists.filter { $0.id != id })
    }

    // MARK: Both

    /// Every collection a publication belongs to.
    ///
    /// `collections-and-reading-lists`: "a publication may belong to any number of
    /// collections". This is how a detail screen asks which.
    public func collections(containing member: String) -> [PublicationCollection] {
        collections.filter { $0.members.contains(member) }
    }

    /// Forgets everything a source defined, for when the source itself is removed.
    ///
    /// Local groupings are untouched: a reader's own collection is theirs, even if every
    /// publication in it came from a server they just removed.
    public func removingAll(from sourceID: UUID) -> Shelves {
        Shelves(
            collections: collections.filter { $0.origin != .server(sourceID) },
            lists: lists.filter { $0.origin != .server(sourceID) }
        )
    }
}
