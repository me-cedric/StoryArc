import Foundation
import StoryArcCore
import Testing

@testable import StoryArc

/// The publication page of task 2.23d: no cover, with progress, and on an offline source.
@Suite("Detail presentation")
struct DetailPresentationTests {
    private let publication = TestPublications.make(1)
    private let home = URL(filePath: "/Users/reader", directoryHint: .isDirectory)
    private let file = URL(filePath: "/Users/reader/Comics/Saga/1.cbz")

    private func progress(_ page: Int, finished: Bool = false) -> ReadingProgress {
        ReadingProgress(
            identity: publication.identity, position: .page(index: page, of: 24),
            isFinished: finished, updatedAt: Date()
        )
    }

    @Test("A publication with no cover and no progress offers Read and names its folder")
    func noCover() {
        let detail = DetailPresentation.make(
            publication: publication, location: file, isReachable: true, progress: nil, hasCover: false, home: home
        )
        #expect(detail.primary == .read)
        #expect(!detail.hasCover)
        #expect(detail.whereItLives == "~/Comics/Saga")
        #expect(!detail.isGrey)
    }

    @Test("With progress the one action is Continue at the page; finished offers Read again")
    func withProgress() {
        let partway = DetailPresentation.make(
            publication: publication, location: file, isReachable: true, progress: progress(11),
            hasCover: true, home: home
        )
        #expect(partway.primary == .continue(page: 12, of: 24))

        let finished = DetailPresentation.make(
            publication: publication, location: file, isReachable: true, progress: progress(23, finished: true),
            hasCover: true, home: home
        )
        #expect(finished.primary == .readAgain)

        let atStart = DetailPresentation.make(
            publication: publication, location: file, isReachable: true, progress: progress(0),
            hasCover: true, home: home
        )
        #expect(atStart.primary == .read)
    }

    @Test("On an offline source the action is absent, the page is grey, and the volume is named")
    func offlineSource() {
        let away = URL(filePath: "/Volumes/NAS/Comics/Saga/1.cbz")
        let detail = DetailPresentation.make(
            publication: publication, location: away, isReachable: false, progress: progress(3),
            hasCover: true, home: home
        )
        #expect(detail.primary == .unavailable)
        #expect(detail.isGrey)
        #expect(detail.whereItLives == "NAS")

        let nowhere = DetailPresentation.make(
            publication: publication, location: nil, isReachable: false, progress: nil, hasCover: false, home: home
        )
        #expect(nowhere.primary == .unavailable)
        #expect(nowhere.whereItLives.isEmpty)
    }

    @Test("A folder outside the home directory is named in full")
    func folderOutsideHome() {
        let volume = URL(filePath: "/Volumes/Comics/Saga/1.cbz")
        #expect(DetailPresentation.folderName(of: volume, home: home) == "/Volumes/Comics/Saga")
    }
}
