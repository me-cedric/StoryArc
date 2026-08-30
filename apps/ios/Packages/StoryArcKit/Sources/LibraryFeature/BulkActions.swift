internal import Foundation

internal import Persistence
internal import StoryArcCore

/// What the reader has picked, and whether they are picking at all.
///
/// `collections-and-reading-lists` wants publications "selected in bulk from the library".
/// A mode rather than a checkbox on every cover for ever: the library is looked at far more
/// often than it is edited, and a grid wearing forty checkboxes is a filing cabinet.
struct LibrarySelection: Equatable {
    private(set) var ids: Set<String> = []

    /// Whether a tap picks rather than opens.
    private(set) var isActive = false

    var count: Int { ids.count }

    mutating func begin() {
        isActive = true
        ids = []
    }

    /// Leaves the mode and forgets what was picked.
    ///
    /// The clear way out the requirement asks for, and one action rather than two: a reader
    /// who leaves selection mode has finished selecting, and asking them to also empty the
    /// set would leave the library holding a decision they had already abandoned.
    mutating func end() {
        isActive = false
        ids = []
    }

    mutating func toggle(_ id: String) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }
}

/// What a bulk action did, so one action can put it back.
///
/// `collections-and-reading-lists`: a bulk mark-read "is undoable for 10 seconds". One undo
/// for the set, not one per publication — a reader who marked forty issues read by mistake
/// is not going to tap Undo forty times, and the tenth second would arrive first.
struct BulkUndo: Identifiable, Equatable {
    let id = UUID()
    let kind: Kind

    /// What actually moved. Deliberately not the selection: an undo that put back what was
    /// never taken would unread a publication the reader finished weeks ago.
    let ids: Set<String>

    enum Kind: Equatable {
        case collection(UUID)
        case list(UUID)
        case read(Bool)
        case kept

        /// A local reading list copied onto a server, and the list the server made of it.
        ///
        /// The source rather than its address: an undo resolves the key out of the secure
        /// store when it runs, so a record waiting out its ten seconds holds no secret.
        case promoted(sourceID: String, listID: Int)
    }
}

/// Bulk actions: the single-publication paths, applied to a set.
///
/// Every one of these answers with what it changed rather than with nothing, because the
/// undo is built from the change. ``BulkSelection`` works out what that is; this carries it
/// out through the same calls one publication already goes through.
extension LibraryModel {
    /// Adds a whole selection to a collection.
    @discardableResult
    func add(selection: Set<String>, toCollection id: UUID) -> Set<String> {
        guard let collection = shelves.collections.first(where: { $0.id == id }) else { return [] }
        let joining = BulkSelection.joining(selection, of: collection)
        guard !joining.isEmpty else { return [] }
        add(joining, toCollection: id)
        return joining
    }

    func remove(_ members: Set<String>, fromCollection id: UUID) {
        shelves = shelves.removing(members, from: id)
        shelvesStore?.save(shelves)
    }

    /// Appends a whole selection to a reading list, in the order the library is showing it.
    @discardableResult
    func append(selection: Set<String>, toList id: UUID) -> [String] {
        guard let list = shelves.lists.first(where: { $0.id == id }) else { return [] }
        let entries = BulkSelection.appending(selection, to: list, inOrderOf: visible.map(\.id))
        guard !entries.isEmpty else { return [] }
        append(entries, toList: id)
        return entries
    }

    /// Marks a whole selection read or unread, one publication at a time.
    ///
    /// The single path, repeated: ``mark(_:read:)`` also tells the server the publication
    /// came from, and a bulk version that wrote straight to the progress store would leave
    /// forty chapters marked read here and unread on Kavita.
    @discardableResult
    func mark(selection: Set<String>, read: Bool) async -> Set<String> {
        let changing = BulkSelection.marking(
            selection, read: read, finished: finishedPublications
        )
        for id in changing {
            guard let publication = publications.first(where: { $0.id == id }) else { continue }
            await mark(publication, read: read)
        }
        return changing
    }

    /// Puts a whole selection back the way it was.
    func undo(_ record: BulkUndo) async {
        switch record.kind {
        case let .collection(id):
            remove(record.ids, fromCollection: id)
        case let .list(id):
            for entry in record.ids { remove(entry, fromList: id) }
        case let .read(wasRead):
            _ = await mark(selection: record.ids, read: !wasRead)
        case .kept:
            forgetKept(record.ids)
        case let .promoted(sourceID, listID):
            await withdraw(listID, from: sourceID)
        }
    }
}
