import Foundation
import Testing

@testable import SettingsFeature
@testable import StoryArcCore

/// What the chooser shows, and what it does when the platform says no.
///
/// The three rules `settings-and-about` and `design.md` agree on: the chooser shows what was
/// *applied* rather than what was asked for, the shown value moves only when the platform
/// confirms, and a refusal is not retried.
@Suite("The app icon chooser's state")
@MainActor
struct AppIconStoreTests {

    /// A platform that can be told to refuse, and that counts what it was asked.
    ///
    /// A class rather than a struct because the store holds the closures and the test holds
    /// the counter, and both have to see the same one.
    @MainActor
    private final class FakePlatform {
        var current: AppIconChoice = .ink
        var accepts = true
        /// Every face the store asked for, in order. The count is what proves nothing retries.
        private(set) var asked: [AppIconChoice] = []
        /// Set when the answer is to be delivered by the test rather than immediately, which
        /// is how "the platform has not answered yet" is reached.
        var pending: (@MainActor (Bool) -> Void)?

        var seam: AppIconPlatform {
            AppIconPlatform(
                applied: { self.current },
                apply: { choice, done in
                    self.asked.append(choice)
                    let answer = self.accepts
                    let settle: @MainActor (Bool) -> Void = { accepted in
                        if accepted { self.current = choice }
                        done(accepted)
                    }
                    if self.pending == nil { settle(answer) } else { self.pending = settle }
                }
            )
        }

        /// Delivers the answer the platform was sitting on.
        func answer(_ accepted: Bool) {
            let settle = pending
            pending = nil
            settle?(accepted)
        }
    }

    @Test("It opens showing whatever the platform is drawing, not the default")
    func readsThePlatformOnInit() {
        let platform = FakePlatform()
        platform.current = .arc
        #expect(AppIconStore(platform: platform.seam).applied == .arc)
    }

    /// The reinstall-and-restore case. An icon can change without this screen: a restore, an
    /// older build, a reinstall. `alternateIconName` is the truth and there is nothing else
    /// to be wrong.
    @Test("Reconciling picks up an icon set outside the chooser")
    func reconciles() {
        let platform = FakePlatform()
        let store = AppIconStore(platform: platform.seam)
        #expect(store.applied == .ink)

        platform.current = .bloom
        store.reconcile()
        #expect(store.applied == .bloom)
    }

    @Test("A face the platform accepts becomes the one in use")
    func appliesAFace() {
        let platform = FakePlatform()
        let store = AppIconStore(platform: platform.seam)
        store.choose(.paper)
        #expect(store.applied == .paper)
        #expect(store.refused == nil)
        #expect(platform.asked == [.paper])
    }

    /// The whole reason the completion handler is the seam. If the store moved on the call
    /// rather than on the answer, the chooser would mark a row the home screen disagrees with
    /// for as long as the platform took to reply — and for ever if it replied with an error.
    @Test("Nothing moves while the platform has not answered")
    func waitsForTheAnswer() {
        let platform = FakePlatform()
        platform.pending = { _ in }
        let store = AppIconStore(platform: platform.seam)

        store.choose(.arc)
        #expect(store.applied == .ink, "the chooser moved before the platform agreed")
        #expect(store.refused == nil)

        platform.answer(true)
        #expect(store.applied == .arc)
    }

    @Test("A refusal names the face still in use and the one that was asked for")
    func refusal() {
        let platform = FakePlatform()
        platform.current = .mono
        platform.accepts = false
        let store = AppIconStore(platform: platform.seam)

        store.choose(.paper)
        #expect(store.applied == .mono, "the icon still in use is not what the chooser shows")
        #expect(store.refused == .paper)
    }

    /// "It does not retry silently, because an icon that changes minutes later with no action
    /// is indistinguishable from a bug." One press, one ask, ever.
    @Test("A refusal is asked once and never again on its own")
    func doesNotRetry() {
        let platform = FakePlatform()
        platform.accepts = false
        let store = AppIconStore(platform: platform.seam)

        store.choose(.arc)
        #expect(platform.asked == [.arc])

        // Everything a screen does afterwards short of another press.
        store.reconcile()
        store.reconcile()
        #expect(platform.asked == [.arc], "something retried a refused change")
        #expect(store.refused == .arc)
    }

    @Test("Pressing something else clears the refusal")
    func aSecondPressClearsIt() {
        let platform = FakePlatform()
        platform.accepts = false
        let store = AppIconStore(platform: platform.seam)
        store.choose(.arc)
        #expect(store.refused == .arc)

        platform.accepts = true
        store.choose(.bloom)
        #expect(store.refused == nil)
        #expect(store.applied == .bloom)
    }

    /// A double tap on the row already marked. Asking iOS for the icon it is already drawing
    /// would present the system alert for a change nobody made.
    @Test("Choosing the face already in use asks the platform nothing")
    func choosingTheCurrentFaceIsANoOp() {
        let platform = FakePlatform()
        platform.current = .paper
        let store = AppIconStore(platform: platform.seam)

        store.choose(.paper)
        #expect(platform.asked.isEmpty, "the platform was asked for an icon it already draws")
        #expect(store.applied == .paper)
    }

    /// Returning to the default goes by the same route as any other choice — and the value it
    /// hands UIKit is `nil`, which is that platform's spelling of the primary icon.
    @Test("The default is chosen the same way as any other face")
    func returningToTheDefault() {
        let platform = FakePlatform()
        platform.current = .arc
        let store = AppIconStore(platform: platform.seam)

        store.choose(.ink)
        #expect(store.applied == .ink)
        #expect(platform.asked == [.ink])
        #expect(AppIconChoice.ink.alternateIconName == nil)
    }
}
