import SwiftUI
import StoryArcCore
import Testing

@testable import LibraryFeature

/// D3's naming, in the unit each kind of position already keeps.
@Suite("A conflict position is named for the reader")
@MainActor
struct SyncConflictNoticeTests {
    private let notice = SyncConflictNotice(conflicts: .constant([]), progress: nil)

    /// Whether this host resolves the catalogue. Xcode 26 answers a host lookup with the key,
    /// so the numbers a format puts in cannot be seen there; Xcode 27 resolves it.
    private var resolves: Bool { notice.label(.page(index: 4, of: 10)) != "sync.position.page" }

    @Test("A page position is named by its own index, one-based")
    func aPagePositionIsNamedByIndex() {
        let label = notice.label(.page(index: 4, of: 10))
        #expect(resolves ? label == "page 5 of 10" : label == "sync.position.page")
    }

    @Test("A reflowable position is named by its fraction, as a percentage")
    func aReflowablePositionIsNamedByPercent() {
        let label = notice.label(.reflowable(progression: 0.5, locator: "{}"))
        #expect(resolves ? label == "50%" : label == "sync.position.percent")
    }
}
