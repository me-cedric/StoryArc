import Foundation
import Testing

@testable import StoryArcCore

@Suite("Folder snapshot")
struct FolderSnapshotTests {
    private let epoch = Date(timeIntervalSince1970: 1_000_000)

    private func entry(_ path: String, at offset: TimeInterval = 0, size: Int64 = 10) -> FolderSnapshot.Entry {
        FolderSnapshot.Entry(path: path, modified: epoch.addingTimeInterval(offset), size: size)
    }

    @Test("A file that appeared is added")
    func appearing() throws {
        // `local-library`: a file added to a watched folder "appears in the library within
        // 10 seconds without a manual refresh".
        let snapshot = FolderSnapshot([entry("/a.cbz")])
        let change = try #require(snapshot.change(to: [entry("/a.cbz"), entry("/b.cbz")]))
        #expect(change.added.map(\.path) == ["/b.cbz"])
        #expect(change.changed.isEmpty)
        #expect(change.removed.isEmpty)
    }

    @Test("A file that went is removed")
    func disappearing() throws {
        let snapshot = FolderSnapshot([entry("/a.cbz"), entry("/b.cbz")])
        let change = try #require(snapshot.change(to: [entry("/a.cbz")]))
        #expect(change.removed == ["/b.cbz"])
        #expect(change.added.isEmpty)
    }

    @Test("A file is unchanged when neither its date nor its size moved")
    func unchanged() throws {
        // The point of the comparison. `local-library` asks the app to reconcile "rather
        // than re-reading every archive", and this is what says which archives to skip.
        let snapshot = FolderSnapshot([entry("/a.cbz"), entry("/b.cbz")])
        let change = try #require(snapshot.change(to: [entry("/a.cbz"), entry("/b.cbz")]))
        #expect(change.isEmpty)
        #expect(change.toIndex.isEmpty)
    }

    @Test("A file whose date moved is re-read")
    func dateMoved() throws {
        // A file replaced with one of the same length keeps its size, so the date has to
        // count on its own.
        let snapshot = FolderSnapshot([entry("/a.cbz")])
        let change = try #require(snapshot.change(to: [entry("/a.cbz", at: 60)]))
        #expect(change.changed.map(\.path) == ["/a.cbz"])
    }

    @Test("A file whose size moved is re-read")
    func sizeMoved() throws {
        // And a file restored from a backup keeps its date, so the size has to count too.
        let snapshot = FolderSnapshot([entry("/a.cbz")])
        let change = try #require(snapshot.change(to: [entry("/a.cbz", size: 99)]))
        #expect(change.changed.map(\.path) == ["/a.cbz"])
    }

    @Test("A walk that found nothing removes nothing")
    func emptyWalkRemovesNothing() {
        // Learnt on a device. A folder whose permission has gone stale, or a provider that
        // has not finished mounting, walks as empty — and reading that as "the reader
        // deleted every book" empties their library.
        let snapshot = FolderSnapshot([entry("/a.cbz"), entry("/b.cbz")])
        #expect(snapshot.change(to: []) == nil)
    }

    @Test("A walk that found nothing does not overwrite a good snapshot")
    func emptyWalkKeepsTheSnapshot() {
        // The other half of the same guard. Throwing the snapshot away would make the pass
        // after the provider came back see every file as new and re-read the whole library.
        let snapshot = FolderSnapshot([entry("/a.cbz")])
        #expect(snapshot.updated(to: []).entries.keys.sorted() == ["/a.cbz"])
    }

    @Test("An empty folder that was always empty is not a refusal")
    func emptyStaysEmpty() throws {
        // Nothing to protect: a folder that held nothing and still holds nothing has no
        // snapshot worth keeping, and refusing here would mean a genuinely empty library
        // never got its first file.
        let change = try #require(FolderSnapshot().change(to: []))
        #expect(change.isEmpty)
    }

    @Test("A snapshot follows the walk it was updated to")
    func updating() {
        let snapshot = FolderSnapshot([entry("/a.cbz")]).updated(to: [entry("/b.cbz")])
        #expect(snapshot.entries.keys.sorted() == ["/b.cbz"])
    }

    @Test("What has to be opened is the added and the changed, and nothing else")
    func onlyTheDifference() throws {
        let snapshot = FolderSnapshot([entry("/a.cbz"), entry("/b.cbz"), entry("/c.cbz")])
        let change = try #require(
            snapshot.change(to: [entry("/a.cbz"), entry("/b.cbz", at: 60), entry("/d.cbz")])
        )
        #expect(change.toIndex.map(\.path).sorted() == ["/b.cbz", "/d.cbz"])
        #expect(change.removed == ["/c.cbz"])
    }
}
