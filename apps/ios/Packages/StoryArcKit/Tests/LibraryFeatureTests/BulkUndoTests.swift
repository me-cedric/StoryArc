import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// What taking the undo offer gives a reader back.
///
/// `collections-and-reading-lists`: marking a collection or a list read updates "every
/// member's read state" and "the action is undoable for 10 seconds". The ten seconds are the
/// bar's; what comes back when the offer is taken is this.
///
/// Only what the action changed comes back. That is the whole difficulty: the record holds the
/// change, never the selection, so an undo cannot unread a publication the reader finished
/// last month, and cannot take a publication out of a collection they put there last week.
/// Both of those are silent losses — nothing draws an error, the reader simply has less than
/// they had.
///
/// Android's `BulkUndoTest` asserts these cases one for one.
@Suite("Bulk undo")
@MainActor
struct BulkUndoTests {

    // MARK: - Fixtures

    private func issue(_ number: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/Crossover/\(number).cbz"),
            format: .cbz,
            displayTitle: "Crossover #\(number)",
            series: "Crossover",
            number: number,
            origin: .inferred
        )
    }

    private func temporary() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "bulk-undo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Membership

    @Test("Undoing an add takes out what was added and leaves what was already there")
    func undoingAnAddKeepsTheEarlierMember() async {
        // The member that was already in the collection is not part of what the action
        // changed, so it must survive the undo. A record built from the selection instead of
        // the change would take it out, and nothing on screen would say so.
        let model = LibraryModel()
        model.create(collection: "Image Comics")
        guard let id = model.shelves.collections.first?.id else {
            Issue.record("no collection was made")
            return
        }
        model.add(["a"], toCollection: id)

        let changed = model.add(selection: ["a", "b", "c"], toCollection: id)
        #expect(changed == ["b", "c"])

        await model.undo(BulkUndo(kind: .collection(id), ids: changed))

        #expect(model.shelves.collections.first?.members == ["a"])
    }

    @Test("Undoing an append takes out what was appended and leaves the order of the rest")
    func undoingAnAppendKeepsTheOrder() async {
        let model = LibraryModel()
        model.create(list: "Crossover")
        guard let id = model.shelves.lists.first?.id else {
            Issue.record("no list was made")
            return
        }
        model.append(["a", "b"], toList: id)

        await model.undo(BulkUndo(kind: .list(id), ids: ["b"]))

        #expect(model.shelves.lists.first?.entries == ["a"])
    }

    @Test("An undo reaches the shelf it names and no other")
    func undoIsPerShelf() async {
        let model = LibraryModel()
        model.create(collection: "Image Comics")
        model.create(collection: "To read with my kid")
        let ids = model.shelves.collections.map(\.id)
        guard ids.count == 2 else {
            Issue.record("two collections were expected")
            return
        }
        for id in ids { model.add(["a"], toCollection: id) }

        await model.undo(BulkUndo(kind: .collection(ids[0]), ids: ["a"]))

        #expect(model.shelves.collections[0].members.isEmpty)
        #expect(model.shelves.collections[1].members == ["a"])
    }

    // MARK: - Read state

    @Test("Undoing a mark read returns exactly what the mark changed")
    func undoingAMarkReturnsWhatItChanged() async throws {
        // The scenario's two halves in one run: every member is marked, and the undo puts the
        // reader back where they were — including the entry they had finished before, which
        // the mark never touched and the undo must not touch either.
        let folder = try temporary()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try ProgressStore(url: folder.appending(path: "progress.store"))

        let model = LibraryModel(progress: store)
        let entries = [issue("1"), issue("2"), issue("3")]
        model.publications = entries
        await model.mark(entries[0], read: true)
        let alreadyFinished: Set<String> = [entries[0].id]
        try #require(model.finishedPublications == alreadyFinished)

        let members = Set(entries.map(\.id))
        let changed = await model.mark(selection: members, read: true)
        #expect(model.finishedPublications == members)
        #expect(changed == [entries[1].id, entries[2].id])

        await model.undo(BulkUndo(kind: .read(true), ids: changed))

        #expect(model.finishedPublications == alreadyFinished)
    }
}
