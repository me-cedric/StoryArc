import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// 10.4: a reconcile that runs before the first walk finishes must not re-read the folder.
///
/// `reconcile(_:)` fell back to an empty `FolderSnapshot()` when the folder had none yet,
/// which compared real files to nothing and reported every one of them "added" — a provider
/// event, or a return from the reader, during the running scan's first walk re-indexed the
/// whole folder a second time, in parallel with the scan already doing it.
@Suite("Reconcile before the first walk finishes")
@MainActor
struct LibraryReconcileGateTests {
    private func temporaryFolder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "reconcile-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let corpus = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: corpus.appending(path: "manifest.json").path) {
                return corpus
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found — expected packages/test-fixtures above \(#filePath)")
    }()

    @Test("A folder with no snapshot yet is left to the running scan")
    func noSnapshotIsLeftAlone() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.copyItem(
            at: Self.corpus.appending(path: "comics/single-page.cbz"),
            to: folder.appending(path: "single-page.cbz")
        )

        let model = LibraryModel()
        // No entry in `snapshots` for this folder: exactly the state the running scan's
        // first walk leaves it in before it finishes.
        await model.reconcile(folder)

        #expect(model.publications.isEmpty, "reconcile indexed a folder the scan already owns")
        #expect(model.snapshots[folder.path] == nil)
    }

    @Test("A folder with a snapshot, even an empty one, is reconciled")
    func anEmptySnapshotIsStillReconciled() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.copyItem(
            at: Self.corpus.appending(path: "comics/single-page.cbz"),
            to: folder.appending(path: "single-page.cbz")
        )

        let model = LibraryModel()
        model.snapshots[folder.path] = FolderSnapshot()
        await model.reconcile(folder)

        #expect(model.publications.count == 1, "a real snapshot should still let reconcile index a new file")
        #expect(model.snapshots[folder.path] != nil)
    }
}
