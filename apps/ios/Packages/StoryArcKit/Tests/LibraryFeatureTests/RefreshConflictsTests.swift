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
}
