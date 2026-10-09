import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// The holder task 2.9 added so a conflict a background refresh finds reaches the library
/// view, not only the series screen's own pull. ``LibraryView`` cannot hold this state
/// itself — it is at its 400-line cap — so ``RefreshConflicts`` is a plain object beside it,
/// proved on its own here with no view in the way.
///
/// `.serialized`: `RefreshConflicts.shared` is process-wide state, the same reason
/// `SmbClientTests` and `SmbReconnectTests` serialize.
@MainActor
@Suite("Refresh conflicts", .serialized)
struct RefreshConflictsTests {

    private func conflict(_ title: String = "Lantern Green #7") -> KavitaConflict {
        KavitaConflict(
            title: title,
            resolved: ReadingProgress(
                identity: PublicationIdentity(normalizedPath: "/a.cbz"),
                position: .page(index: 10, of: 20),
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
            discarded: .page(index: 3, of: 20)
        )
    }

    // Every test starts from, and must leave, an empty holder: this is process-wide state.
    init() { RefreshConflicts.shared.clear() }

    @Test("A report with nothing in it is not a report at all")
    func emptyReportDoesNothing() {
        RefreshConflicts.shared.report([])

        #expect(RefreshConflicts.shared.conflicts.isEmpty)
    }

    @Test("What one refresh found is what the holder then carries")
    func reportIsCarried() {
        let found = [conflict()]

        RefreshConflicts.shared.report(found)

        #expect(RefreshConflicts.shared.conflicts == found)
    }

    @Test("A second source's conflicts join the first refresh's, rather than replacing them")
    func conflictsAccumulate() {
        RefreshConflicts.shared.report([conflict("Lantern Green #7")])
        RefreshConflicts.shared.report([conflict("Night Market #2")])

        #expect(RefreshConflicts.shared.conflicts.count == 2)
    }

    @Test("The reader answering clears every conflict the holder had")
    func clearEmpties() {
        RefreshConflicts.shared.report([conflict()])

        RefreshConflicts.shared.clear()

        #expect(RefreshConflicts.shared.conflicts.isEmpty)
    }

    private func synced(_ path: String, kept: Int, discarded: Int) -> ProgressPull.Conflict {
        ProgressPull.Conflict(
            resolved: ReadingProgress(
                identity: PublicationIdentity(normalizedPath: path),
                position: .page(index: kept, of: 20),
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
            discarded: .page(index: discarded, of: 20)
        )
    }

    @Test("Library sync, task 5.4: one conflict reaches the notice named by its file")
    func oneSyncConflictIsNamed() throws {
        SyncConflicts.report([synced("/Books/Marsh Auburn.cbz", kept: 11, discarded: 4)])

        let shown = try #require(RefreshConflicts.shared.conflicts.first)
        #expect(RefreshConflicts.shared.conflicts.count == 1)
        #expect(shown.title == "Marsh Auburn")
        #expect(shown.resolved.position == .page(index: 11, of: 20))
        #expect(shown.discarded == .page(index: 4, of: 20))
        RefreshConflicts.shared.clear()
    }

    @Test("Library sync, task 5.4: several conflicts reach the notice, and none add nothing")
    func severalSyncConflictsAreCounted() {
        SyncConflicts.report([])
        #expect(RefreshConflicts.shared.conflicts.isEmpty)

        SyncConflicts.report([
            synced("content://tree/primary%3ABooks%2FTide.cbz", kept: 7, discarded: 2),
            synced("/Books/Night Market.epub", kept: 5, discarded: 1),
        ])
        #expect(RefreshConflicts.shared.conflicts.map(\.title) == ["Tide", "Night Market"])
        RefreshConflicts.shared.clear()
    }
}
