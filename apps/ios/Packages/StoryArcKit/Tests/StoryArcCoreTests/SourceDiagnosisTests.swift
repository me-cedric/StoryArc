import Foundation
import Testing

@testable import StoryArcCore

/// What a source's detail screen says about a source, and what it offers to do.
///
/// `sources` names five fields and five actions. The audit found the settings list carrying
/// two of the fields and one of the actions, so every case here is a clause of the
/// `Diagnosing a source` scenario. Android's `SourceDiagnosisTest` asserts the same table in
/// the same order.
@Suite("Source diagnosis")
struct SourceDiagnosisTests {

    private func source(
        _ name: String = "Comics",
        kind: SourceKind = .kavitaServer,
        state: SourceConnectionState = .connected,
        syncedAt: Date? = nil
    ) -> Source {
        Source(displayName: name, kind: kind, state: state, lastSuccessfulSync: syncedAt)
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

    // MARK: - The five fields

    @Test("The state and the last successful sync are the source's own")
    func reportsStateAndSync() {
        let moment = Date(timeIntervalSince1970: 1_000)
        let diagnosis = SourceDiagnosis.of(
            source(state: .connected, syncedAt: moment),
            itemCount: 4,
            downloads: []
        )

        #expect(diagnosis.state == .connected)
        #expect(diagnosis.lastSuccessfulSync == moment)
        #expect(diagnosis.itemCount == 4)
    }

    @Test("A connected source has no error to report")
    func connectedHasNoFailure() {
        #expect(SourceDiagnosis.of(source(state: .connected), itemCount: 0, downloads: []).failure == nil)
        #expect(SourceDiagnosis.of(source(state: .connecting), itemCount: 0, downloads: []).failure == nil)
    }

    @Test("An unreachable source reports when it stopped answering")
    func unreachableCarriesItsMoment() {
        let since = Date(timeIntervalSince1970: 90)

        let diagnosis = SourceDiagnosis.of(
            source(state: .unreachable(since: since)),
            itemCount: 0,
            downloads: []
        )

        #expect(diagnosis.failure == .unreachable(since: since))
    }

    @Test("A refused credential reports the reason, which is what a reader can act on")
    func unauthorizedCarriesItsReason() {
        let diagnosis = SourceDiagnosis.of(
            source(state: .unauthorized(reason: "Key refused")),
            itemCount: 0,
            downloads: []
        )

        #expect(diagnosis.failure == .unauthorized(reason: "Key refused"))
    }

    @Test("The bytes are this source's finished downloads and nobody else's")
    func countsOnlyItsOwnFinishedDownloads() {
        let mine = source()
        let other = UUID()

        let diagnosis = SourceDiagnosis.of(
            mine,
            itemCount: 3,
            downloads: [
                download(from: mine.id, bytes: 100),
                download(from: mine.id, bytes: 200),
                // Another source's, and one of this source's that is not on disk yet.
                download(from: other, bytes: 4_000),
                download(from: mine.id, bytes: 50, state: .queued)
            ]
        )

        #expect(diagnosis.downloadCount == 2)
        #expect(diagnosis.downloadedBytes == 300)
    }

    // MARK: - The five actions

    @Test("A source with downloads offers all five actions, destructive last")
    func offersEveryAction() {
        let mine = source()

        let diagnosis = SourceDiagnosis.of(
            mine,
            itemCount: 1,
            downloads: [download(from: mine.id, bytes: 10)]
        )

        #expect(diagnosis.actions == [.testConnection, .refresh, .clearCache, .removeDownloads, .remove])
    }

    @Test("Nothing downloaded means nothing to offer to delete")
    func hidesRemoveDownloadsWithNothingOnDisk() {
        let diagnosis = SourceDiagnosis.of(source(), itemCount: 1, downloads: [])

        #expect(!diagnosis.actions.contains(.removeDownloads))
    }

    @Test("A source the reader did not add is not one they can remove")
    func hidesRemoveForAnUnremovableSource() {
        let diagnosis = SourceDiagnosis.of(
            source("On this device", kind: .localFolder),
            itemCount: 2,
            downloads: [],
            isRemovable: false
        )

        #expect(diagnosis.actions == [.testConnection, .refresh, .clearCache])
    }

    @Test("Only the two that delete bytes ask before they happen")
    func namesTheDestructiveActions() {
        #expect(SourceAction.allCases.filter(\.isDestructive) == [.removeDownloads, .remove])
    }
}
