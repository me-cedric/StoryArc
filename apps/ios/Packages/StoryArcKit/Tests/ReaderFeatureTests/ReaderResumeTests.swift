import Foundation
import Testing

import Persistence
import StoryArcCore
@testable import ReaderFeature

/// `reading-progress`: a publication reopens on the page it was left on. The UI walk
/// `ReadingContinuityUITests` proves it on a device; this is the same property held by the
/// model on the host, through the same store.
@MainActor
@Suite("Reader resumes")
struct ReaderResumeTests {
    private static let location: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: candidate.appending(path: "manifest.json").path) {
                return candidate.appending(path: "comics/natural-sort.cbz")
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    private func model(_ store: ProgressStore) -> ReaderModel {
        ReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: Self.location.path),
                format: .cbz,
                displayTitle: "natural-sort.cbz",
                origin: .inferred
            ),
            url: Self.location,
            progress: store
        )
    }

    @Test("A page turned in one reader is the page the next reader opens on")
    func theNextReaderOpensWhereTheLastLeftOff() async throws {
        let store = try ProgressStore.inMemory()
        let first = model(store)
        await first.open(maxPixelSize: 256)
        await first.go(to: 2)

        let second = model(store)
        await second.open(maxPixelSize: 256)

        #expect(second.currentIndex == 2, "reopened on \(second.currentIndex)")
        #expect(second.openCount == 1, "the pager is told once, after the resume has landed")
    }
}
