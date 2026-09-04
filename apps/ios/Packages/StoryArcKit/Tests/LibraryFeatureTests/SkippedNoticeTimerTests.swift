import Foundation
import Testing

@testable import LibraryFeature

/// That the notice has no timer, and no state of its own that a redraw could reset.
///
/// `library-browsing`: the notice "stays until the reader dismisses it or resolves it". What
/// it replaced did the opposite — `ScanSummary` held `dwell = .seconds(6)` and an
/// `@State private var isShowing`, and slept before clearing it.
///
/// **A test that only checked the notice appears would pass against the toast**, which is
/// why this exists at all. The honest assertion is a booted simulator watching the sentence
/// still be there after seven seconds, and that is what
/// `apps/ios/UITests/SkippedNoticeTests.swift` does; this is the part that runs in the host
/// suite on every commit.
///
/// **What text can honestly say, and what it cannot.** It cannot say the notice is visible
/// after six seconds. It can say the view contains no sleep, no timer and no visibility
/// state — which is a structural claim, and it is exactly the structure that made the old
/// one temporary. Paired with ``SkippedPublicationsTests``, which asserts the notice is a
/// pure function of the model's own value, the two together leave nowhere for a countdown to
/// live.
///
/// Android asserts the same thing properly, because Compose's test clock can be advanced:
/// `SkippedNoticeTest` moves it past seven seconds and looks again.
@Suite("The notice is not on a timer")
struct SkippedNoticeTimerTests {

    // The `#filePath` walk lives in ``LibraryFeatureSource``. This file carried a third copy
    // of it — the split that created that type warned a third copy was a third chance for one
    // of them to point at the wrong checkout, and this was already it.

    private static let notice = LibraryFeatureSource.source("Sources/LibraryFeature/SkippedNotice.swift")
    private static let states = LibraryFeatureSource.source("Sources/LibraryFeature/LibraryStates.swift")

    @Test("The notice never sleeps")
    func noSleep() {
        // The whole of the toast's behaviour was `try? await Task.sleep(for: Self.dwell)`.
        #expect(!Self.notice.contains("Task.sleep"))
        #expect(!Self.notice.contains("Duration.seconds"))
        #expect(!Self.notice.contains(".seconds("))
    }

    @Test("The notice keeps no visibility of its own")
    func visibilityIsTheModels() {
        // One `@State`, and it is whether the *list* is open. A second one holding whether
        // the notice is shown is how a countdown gets somewhere to write its answer.
        // Declarations, not mentions: the doc comment says out loud that there is no
        // visibility state here, and counting the words would count that sentence.
        let states = Self.notice.components(separatedBy: "@State private var").count - 1
        #expect(states == 1)
        #expect(Self.notice.contains("@State private var isListShown"))
        #expect(!Self.notice.contains("isShowing"))
    }

    @Test("Nothing in the library's states counts down any more")
    func theDwellIsGone() {
        // `ScanSummary` lived here. Its `dwell` and its `isShowing` countdown both went with
        // it, and the file is where a well-meaning revert would put them back.
        #expect(!Self.states.contains("dwell"))
        #expect(!Self.states.contains("ScanSummary"))
        #expect(!Self.states.contains("Task.sleep"))
    }
}
