import Foundation
import Testing

import Catalogue
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// The undo of a group download, for a member it queued from its catalogue.
///
/// The row is `srv:<source>:opds:<entry>` and the queue keys the download
/// `opds:<source>:<entry>`. An undo by the row's id took nothing back, and the member went
/// on downloading under a bar that said it had been undone. Android asserts the same in
/// `RemoteMemberUndoTest`.
@Suite("Undoing a group download takes back what it queued")
@MainActor
struct RemoteMemberUndoTests {

    private let entry = OpdsEntry(id: "hl09", title: "Harbour Lights 09")

    private let acquisition = OpdsAcquisition(
        href: URL(string: "https://example.invalid/hl09.epub")!,
        mediaType: "application/epub+zip",
        kind: .open
    )

    private func queue() throws -> DownloadQueue {
        let name = "remote-member-undo-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: name, directoryHint: .isDirectory)
        return DownloadQueue(store: DownloadStore(defaults: defaults, directory: directory), settings: { AppSettings() })
    }

    @Test("Undoing a group download takes back a member it queued from its catalogue")
    func undoTakesBackAQueuedMember() throws {
        let queue = try queue()
        let source = UUID()

        let queued = RemoteMemberResolution.enqueue(entry, using: acquisition, sourceID: source, in: queue)
        LibraryModel().forgetKept(Set([queued].compactMap { $0 }), queue: queue)

        #expect(queue.library[queue.downloadID(for: entry.id, sourceID: source)] == nil)
    }

    @Test("A member the reader had already queued is not the group's to take back")
    func anEarlierDownloadIsNotTheGroups() throws {
        let queue = try queue()
        let source = UUID()
        queue.enqueue(entry, using: acquisition, sourceID: source)

        #expect(RemoteMemberResolution.enqueue(entry, using: acquisition, sourceID: source, in: queue) == nil)
        #expect(queue.library[queue.downloadID(for: entry.id, sourceID: source)] != nil)
    }
}
