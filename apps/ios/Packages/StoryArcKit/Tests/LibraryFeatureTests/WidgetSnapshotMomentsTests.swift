import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// When the app may write the home-screen widget's snapshot (close-the-audited-gaps 20.1).
///
/// `ReadingContinuity` writes the snapshot from `continueReading` only once the library has
/// read the positions, and reads them again when the app goes to the background. The first
/// rule keeps a cold launch from clearing the widget; the second gives it the page reached.
@Suite("Widget snapshot moments")
@MainActor
struct WidgetSnapshotMomentsTests {

    private let book = Publication(
        identity: PublicationIdentity(normalizedPath: "/Shelf/Bone.cbz"),
        format: .cbz,
        displayTitle: "Bone",
        origin: .inferred
    )

    private func store() throws -> ProgressStore {
        let folder = URL.temporaryDirectory.appending(path: "widget-moments-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try ProgressStore(url: folder.appending(path: "progress.store"))
    }

    private func snapshot(of model: LibraryModel) -> ReadingSnapshot? {
        let first = model.continueReading.first
        return ReadingSnapshot(publication: first, fractionRead: first.flatMap(model.readFraction(of:)))
    }

    @Test("A cold launch has not read the positions, so an empty shelf clears nothing")
    func coldLaunchHasNotLoaded() async throws {
        let model = LibraryModel(progress: try store())
        model.publications = [book]

        #expect(!model.hasLoadedProgress)
        #expect(model.continueReading.isEmpty)

        await model.refreshProgress()
        #expect(model.hasLoadedProgress)
    }

    @Test("A read at background carries the page reached since the last read")
    func backgroundReadCarriesThePageReached() async throws {
        let store = try store()
        let model = LibraryModel(progress: store)
        model.publications = [book]
        try await store.save(ReadingProgress(
            identity: book.identity, position: .page(index: 1, of: 11), updatedAt: Date()
        ))
        await model.refreshProgress()
        #expect(snapshot(of: model)?.percentRead == 10)

        // The reader turned pages while the book stayed open; the library has not looked.
        try await store.save(ReadingProgress(
            identity: book.identity, position: .page(index: 5, of: 11), updatedAt: Date()
        ))
        #expect(snapshot(of: model)?.percentRead == 10)

        await model.refreshProgress()
        #expect(snapshot(of: model)?.percentRead == 50)
    }
}
