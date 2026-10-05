import Foundation
@testable import LibraryFeature
import Smb
import StoryArcCore
import Testing

/// A share's first read hands its frontier to the continuation, instead of the continuation
/// walking the share's root a second time.
///
/// `SmbContributorTests` already proves the walk itself resumes from a frontier it is handed.
/// It proves it by passing `first.queue` by hand, which is exactly why it could not see that
/// nothing seeded ``LibraryModel/smbQueues`` — the first read called a wrapper that threw the
/// queue away, so the continuation's cursor fell back to the share's root, listed it again,
/// and adopted every row it already held. The reader saw the number on the source detail
/// screen grow to about twice the share's real one. These tests drive the model, which is
/// where that seam actually is. Android's `SmbFirstReadCarriesItsFrontierTest` is the twin.
@MainActor
@Suite("A share's first read carries its frontier")
struct SmbFirstReadCarriesItsFrontierTests {

    private let sourceID = UUID()
    private let address = SmbAddress(host: "nas.local", share: "Comics")

    private func model(kind: SourceKind = .networkShare) -> LibraryModel {
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [Source(id: sourceID, displayName: "Attic", kind: kind)])
        return model
    }

    /// A root with `count` sibling folders, each holding one file.
    private func wideTree(_ count: Int) -> [String: [SmbEntry]] {
        var tree: [String: [SmbEntry]] = [
            "": (0..<count).map { SmbEntry(name: "d\($0)", path: "d\($0)", isDirectory: true, length: 0) },
        ]
        for index in 0..<count {
            tree["d\(index)"] = [SmbEntry(name: "f.cbz", path: "d\(index)/f.cbz", isDirectory: false, length: 1)]
        }
        return tree
    }

    @Test("The first continuation page resumes the frontier the share read stopped at, not the root")
    func continuationStartsAtTheFrontier() async {
        // Wider than the folder budget, so the first page is proven to stop with folders
        // still unlisted rather than finishing the share.
        let tree = wideTree(SmbContributor.maxFolders + 6)
        var listed: [String] = []
        func list(_ path: String) async throws -> [SmbEntry] { listed.append(path); return tree[path] ?? [] }

        // What `ServerLibrary.read` now does for a share: one page from the share's root, and
        // the frontier it stopped at carried out of the read with the slice.
        let first = await SmbContributor.page(source: sourceID, address: address, queue: [address.path], list: list)
        #expect(first.slice.holdsMore)

        let model = model()
        model.adoptPartialSources(.init(partial: [sourceID], smbQueues: [sourceID: first.queue]))
        #expect(model.smbQueues[sourceID] == first.queue)

        // What `continueReadingShares` then asks its first page for, fallback included.
        listed = []
        let queue = model.smbQueues[sourceID] ?? [address.path]
        let second = await SmbContributor.page(source: sourceID, address: address, queue: queue, list: list)

        // Delete the `smbQueues` seeding in `adoptPartialSources` and both of these fail: the
        // cursor falls back to the share's root, so "" is listed a second time and every row
        // the first page already adopted is counted again.
        #expect(!listed.contains(""))
        let adopted = first.slice.publications + second.slice.publications
        #expect(Set(adopted.map(\.identity.normalizedPath)).count == adopted.count)
        #expect(adopted.count == SmbContributor.maxFolders + 6)
    }

    @Test("A share that finished its read lets its frontier go")
    func finishedShareForgetsItsFrontier() {
        let model = model()
        model.adoptPartialSources(.init(partial: [sourceID], smbQueues: [sourceID: ["d40"]]))

        model.adoptPartialSources(.init())

        #expect(model.smbQueues[sourceID] == nil)
        #expect(model.partialSources[sourceID] == nil)
    }
}
