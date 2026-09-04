internal import Foundation
internal import Observation
#if canImport(UIKit)
internal import UIKit
#endif

internal import StoryArcCore

/// The platform's own answer about the app icon, behind a seam a test can stand in for.
///
/// Two closures rather than a protocol with two methods: there is one real implementation
/// and one fake, the fake differs per test, and a protocol would need a class per case.
/// `Sendable` is unreachable here on purpose — this is main-actor state, because
/// `UIApplication` is.
@MainActor
struct AppIconPlatform {
    /// What the platform says it is drawing, right now. **Not** what anybody stored.
    var applied: @MainActor () -> AppIconChoice

    /// Asks for a face and reports whether the platform accepted it.
    ///
    /// The completion is where a refusal arrives, which is the whole reason this signature
    /// is not `-> Bool`: `setAlternateIconName` returns immediately and answers later, and a
    /// store that treated the return as the answer would move its state before the platform
    /// had agreed to anything.
    var apply: @MainActor (AppIconChoice, @escaping @MainActor (Bool) -> Void) -> Void

    /// Whether the platform offers the choice at all.
    ///
    /// **A third closure, because the requirement asks about a case the other two cannot
    /// express.** `applied` and `apply` describe a platform that answers; this describes one
    /// that never offers. `native-experience` says a chosen icon survives "everything short of
    /// the platform withdrawing the ability" — and a delta rewrite on 2026-09-04 dropped the
    /// withdrawal scenario along with a genuinely unimplementable clause about a stored
    /// preference, leaving the requirement promising a case nothing specified. A verification
    /// pass caught the dangling promise. This is the half that was implementable all along.
    ///
    /// Asked rather than inferred from a refusal: a refusal is per-attempt and tells a reader
    /// their *last* choice failed, which is a different sentence from *this device does not do
    /// this*. Answering the second only after a reader has tried is the pre-emptive affordance
    /// the scenario asked for and did not get.
    var isOffered: @MainActor () -> Bool

    #if canImport(UIKit)
    /// UIKit, which is the only implementation that ships.
    ///
    /// **The system alert is not suppressed.** iOS presents one on every change by default.
    /// Suppressing it is undocumented and rides on overriding a private delegate method, so
    /// the app leaves it alone: `settings-and-about` says the app "does not present a system
    /// alert it did not ask for", and the platform's own alert is the platform's. Fighting it
    /// is how apps break on the next OS.
    static var uiKit: AppIconPlatform {
        AppIconPlatform(
            applied: { AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName) },
            apply: { choice, done in
                UIApplication.shared.setAlternateIconName(choice.alternateIconName) { error in
                    // Hops nowhere: UIKit already calls back on the main queue, and the
                    // closure is main-actor-isolated so the compiler holds us to it.
                    MainActor.assumeIsolated { done(error == nil) }
                }
            },
            isOffered: { UIApplication.shared.supportsAlternateIcons }
        )
    }
    #endif

    /// Whatever this build has.
    ///
    /// `StoryArcKit` also builds for macOS so the pure suites can run on the host without a
    /// simulator (ADR-0003), and there is no alternate-icon API there. The fallback refuses
    /// every change rather than pretending to accept one — a screen nobody draws, answering
    /// honestly if anybody ever does.
    static var current: AppIconPlatform {
        #if canImport(UIKit)
        uiKit
        #else
        AppIconPlatform(
            applied: { .default },
            apply: { _, done in done(false) },
            isOffered: { false }
        )
        #endif
    }
}

/// What the icon chooser shows and what pressing a row does.
///
/// **It holds no preference.** iOS persists `alternateIconName` itself, so a stored choice
/// beside it would be a second answer to a question the platform already answers — and the
/// two would disagree the first time a change was refused. `settings-and-about` asks the
/// chooser to show what was *applied*; ``applied`` is read from the platform on every
/// appearance and moves only when the platform confirms.
///
/// Android's `AppIconSwitcher` is the counterpart, and it is a different shape because the
/// platform is: there is no `setAlternateIconName` there, so the swap is a sequence of
/// component writes with an invariant of its own.
@MainActor
@Observable
final class AppIconStore {
    /// The face the platform says is on the home screen.
    private(set) var applied: AppIconChoice

    /// The face a reader asked for and did not get, if the last change was refused.
    ///
    /// `settings-and-about`: a refusal "says the icon could not be changed and which one is
    /// still in use". Which one is still in use is ``applied``; this is the other half, so
    /// the message can name both without the screen having to remember what was pressed.
    ///
    /// **Nothing retries it.** "It does not retry silently, because an icon that changes
    /// minutes later with no action is indistinguishable from a bug." Clearing this is a
    /// reader's act — pressing something else, or leaving.
    private(set) var refused: AppIconChoice?

    /// Whether this device offers the choice at all.
    ///
    /// Read once, at init, and never again: `supportsAlternateIcons` is a property of the
    /// platform and the build, not of anything a reader can do while the screen is up, so
    /// re-asking it in ``reconcile()`` would be re-asking a constant.
    ///
    /// **Distinct from a refusal on purpose.** ``refused`` says one attempt failed and names
    /// the face still in use; this says the device never offered the choice, so there is no
    /// attempt to report and no face to name. `native-experience` asks the app to survive
    /// "everything short of the platform withdrawing the ability" — this is the withdrawal.
    let isOffered: Bool

    private let platform: AppIconPlatform

    init(platform: AppIconPlatform) {
        self.platform = platform
        applied = platform.applied()
        isOffered = platform.isOffered()
    }

    /// Asks the platform again.
    ///
    /// Called when the chooser appears, which covers the case the design document calls the
    /// truth: an icon set outside this screen — by a restore, by an older build, by a
    /// reinstall — and a stored preference that would have gone on claiming otherwise.
    func reconcile() {
        applied = platform.applied()
    }

    /// Puts a face on the home screen, and moves nothing until the platform says so.
    func choose(_ choice: AppIconChoice) {
        refused = nil
        // Nothing is asked of a platform that does not offer the choice — the chooser draws
        // no controls in that state, so this is the belt to that screen's braces rather than
        // a branch a reader can reach.
        guard isOffered else { return }
        // A no-op is a no-op. Asking the platform for the icon it is already drawing would
        // present its alert for a change nobody made.
        guard choice != applied else { return }
        platform.apply(choice) { [weak self] accepted in
            guard let self else { return }
            if accepted {
                applied = choice
            } else {
                // The stored choice does not move, because there is no stored choice: what
                // the chooser shows is re-read from the platform, which is still drawing
                // whatever it was drawing.
                applied = platform.applied()
                refused = choice
            }
        }
    }
}
