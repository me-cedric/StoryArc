import Foundation
import Testing

@testable import StoryArcCore

/// Which sentence the removal confirmation shows, and where its figures come from.
///
/// `sources`, *Removing a source*: the app "states how many downloaded files and how much disk
/// space will be freed before asking for confirmation". The confirmation used to say that no
/// files are deleted whatever the source held, so every case here is one clause of that
/// scenario. Android's `SourceRemovalWordingTest` asserts the same table in the same order.
///
/// **Mutation-proved on 2026-09-05**: with the rule changed to `downloadCount > 1`, the two cases
/// built on one download — `oneDownloadNamesTheFiles` and `aWeightlessDownloadStillCounts` —
/// failed by name and the other four stayed green; reverted.
@Suite("Source removal wording")
struct SourceRemovalWordingTests {

    @Test("Nothing downloaded picks the sentence that names only the titles")
    func nothingDownloadedNamesTitlesOnly() {
        let wording = SourceRemovalWording.of(titleCount: 12, downloadCount: 0, downloadedBytes: 0)

        #expect(wording == .titlesOnly(titleCount: 12))
    }

    @Test("One finished download is enough to name the files and what they weigh")
    func oneDownloadNamesTheFiles() {
        // The defect, stated as the assertion. One file on disk is the smallest source for
        // which "no files on your device are deleted" is false.
        let wording = SourceRemovalWording.of(titleCount: 3, downloadCount: 1, downloadedBytes: 5_242_880)

        #expect(wording == .titlesAndDownloads(titleCount: 3, downloadCount: 1, downloadedBytes: 5_242_880))
    }

    @Test("The figures are the arguments' own, neither rounded nor recounted")
    func figuresComeFromTheArguments() {
        let wording = SourceRemovalWording.of(titleCount: 7, downloadCount: 4, downloadedBytes: 1_234)

        guard case let .titlesAndDownloads(titles, downloads, bytes) = wording else {
            Issue.record("expected the download sentence, got \(wording)")
            return
        }
        #expect(titles == 7)
        #expect(downloads == 4)
        #expect(bytes == 1_234)
    }

    @Test("A finished download that weighs nothing is still a file the removal deletes")
    func aWeightlessDownloadStillCounts() {
        // Decided by the count, not the bytes: the sentence for zero bytes would otherwise
        // promise that nothing is deleted while a file goes.
        let wording = SourceRemovalWording.of(titleCount: 1, downloadCount: 1, downloadedBytes: 0)

        #expect(wording == .titlesAndDownloads(titleCount: 1, downloadCount: 1, downloadedBytes: 0))
    }

    @Test("From a diagnosis, the figures are the source's own finished downloads")
    func readsTheDiagnosis() {
        // The same filter the *Downloaded* field uses, so the two cannot disagree: this
        // source's finished downloads count, another source's and a queued one do not.
        let mine = Source(displayName: "Comics", kind: .kavitaServer, state: .connected)
        let diagnosis = SourceDiagnosis.of(
            mine,
            itemCount: 5,
            downloads: [
                download(from: mine.id, bytes: 100),
                download(from: mine.id, bytes: 200),
                download(from: UUID(), bytes: 4_000),
                download(from: mine.id, bytes: 50, state: .queued)
            ]
        )

        #expect(
            SourceRemovalWording.of(diagnosis)
                == .titlesAndDownloads(titleCount: 5, downloadCount: 2, downloadedBytes: 300)
        )
    }

    @Test("A diagnosis with nothing on disk reads as titles only")
    func aBareDiagnosisIsTitlesOnly() {
        let source = Source(displayName: "Attic", kind: .networkShare, state: .connected)
        let diagnosis = SourceDiagnosis.of(source, itemCount: 9, downloads: [])

        #expect(SourceRemovalWording.of(diagnosis) == .titlesOnly(titleCount: 9))
    }

    private func download(
        from sourceID: UUID?,
        bytes: Int64,
        state: Download.State = .finished
    ) -> Download {
        Download(
            id: UUID().uuidString,
            sourceID: sourceID,
            title: "Issue",
            remote: URL(fileURLWithPath: "/tmp/issue.cbz"),
            mediaType: "application/vnd.comicbook+zip",
            state: state,
            downloadedBytes: bytes
        )
    }
}
