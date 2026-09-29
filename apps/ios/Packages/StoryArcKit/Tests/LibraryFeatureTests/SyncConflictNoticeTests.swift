import SwiftUI
import StoryArcCore
import Testing

@testable import LibraryFeature

/// D3's naming, in the unit each kind of position already keeps.
@Suite("A conflict position is named for the reader")
@MainActor
struct SyncConflictNoticeTests {
    private let notice = SyncConflictNotice(conflicts: .constant([]), progress: nil)

    @Test("A page position is named by its own index, one-based")
    func aPagePositionIsNamedByIndex() {
        #expect(notice.label(.page(index: 4, of: 10)) == "page 5 of 10")
    }

    @Test("A reflowable position is named by its fraction, as a percentage")
    func aReflowablePositionIsNamedByPercent() {
        #expect(notice.label(.reflowable(progression: 0.5, locator: "{}")) == "50%")
    }
}
