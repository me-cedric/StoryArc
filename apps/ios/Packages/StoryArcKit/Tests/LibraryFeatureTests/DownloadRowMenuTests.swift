import Testing

@testable import LibraryFeature
import StoryArcCore

/// Task 24.3 of `close-the-audited-gaps`: a transfer's actions are one menu, not up to four
/// buttons 28 pt tall and 8 pt apart. This is what the menu holds, which the view cannot say
/// without a window.
@Suite("The downloads queue's menus")
struct DownloadRowMenuTests {

    @Test("A failed transfer offers Retry, then Remove download alone")
    func failed() {
        #expect(
            DownloadRowMenu.groups(for: .failed(reason: "timed out", attempts: 3), canReorder: false)
                == [[.retry], [.remove]]
        )
    }

    @Test("A held transfer offers Resume, then Remove download alone, whatever held it")
    func held() {
        for pause in [Download.Pause.byReader, .waitingForWiFi, .outOfSpace] {
            #expect(
                DownloadRowMenu.groups(for: .paused(pause), canReorder: false) == [[.resume], [.remove]]
            )
        }
    }

    @Test("A queued transfer can be moved; a running one has started and cannot")
    func reorder() {
        #expect(
            DownloadRowMenu.groups(for: .queued, canReorder: true)
                == [[.pause, .moveEarlier, .moveLater], [.stop]]
        )
        #expect(DownloadRowMenu.groups(for: .running, canReorder: false) == [[.pause], [.stop]])
    }

    @Test("The last row of every menu is a destructive one, alone in its group")
    func destructiveLastAndAlone() {
        let states: [Download.State] = [
            .queued, .running, .paused(.byReader), .failed(reason: "x", attempts: 3),
        ]
        for state in states {
            let groups = DownloadRowMenu.groups(for: state, canReorder: true)
            let last = groups.last
            #expect(last?.count == 1)
            #expect(last?.first?.isDestructive == true)
            #expect(groups.dropLast().joined().allSatisfy { !$0.isDestructive })
        }
    }

    @Test("Pause all and Resume all are a pair, and Cancel all is last and alone")
    func everyTransferAtOnce() {
        #expect(DownloadAllAction.groups == [[.pauseAll, .resumeAll], [.cancelAll]])
        #expect(DownloadAllAction.cancelAll.isDestructive)
        #expect(!DownloadAllAction.pauseAll.isDestructive)
    }
}
