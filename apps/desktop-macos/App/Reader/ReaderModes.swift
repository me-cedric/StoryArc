import Persistence
import StoryArcCore

/// How a page change is drawn in a paged reader.
enum PageChange: Equatable, Sendable {
    /// The new page slides in from the trailing edge, or from the leading edge.
    case slide(fromTrailing: Bool)
    /// A short cross-dissolve, no translation: Fast fade, and what Reduce Motion leaves.
    case fade
    /// No animation: a continuous scroll has no turn, and a change that is not a turn.
    case cut
}

/// The turn, by the mode that runs now.
///
/// `page-transitions`, *Transition modes*: Slide is a paged translation along the reading
/// axis, Fast fade a short cross-dissolve. The next page arrives from the side reading moves
/// towards, so a right-to-left publication slides the other way, as its keys and its click
/// zones do. The mode that runs is `TransitionChoices.effective`, which is already Fast fade
/// under Reduce Motion.
enum PageChanges {
    static let slideSeconds = 0.24
    static let fadeSeconds = 0.15

    static func change(effective: PageTransition, step: Int, isRightToLeft: Bool) -> PageChange {
        guard step != 0 else { return .cut }
        switch effective {
        case .slide, .pageCurl: return .slide(fromTrailing: (step > 0) != isRightToLeft)
        case .fastFade: return .fade
        case .verticalScroll, .horizontalScroll: return .cut
        }
    }
}

/// One row of the transition picker.
struct TransitionRow: Identifiable, Equatable, Sendable {
    let mode: PageTransition
    let titleKey: String
    /// Why the row cannot run now, or `nil` when it can.
    let reasonKey: String?
    /// Whether this is the stored choice, which a row that cannot run still keeps.
    let isChosen: Bool

    var id: String { mode.rawValue }
}

/// The picker, from `TransitionChoices`.
///
/// `page-transitions`, *A mode is unavailable for the content* and *Reduce Motion is on*: a
/// mode that cannot run is listed, marked unavailable with its reason, never silently
/// absent. The curl is the one absence, stated once in a sentence, because nothing the
/// reader can do brings it back before wave 5.
enum TransitionMenu {
    static func rows(_ choices: TransitionChoices) -> [TransitionRow] {
        choices.offered.map { mode in
            TransitionRow(
                mode: mode, titleKey: titleKey(of: mode),
                reasonKey: choices.unavailable[mode].map(reasonKey(of:)), isChosen: mode == choices.chosen
            )
        }
    }

    static func absentCurlKey(_ choices: TransitionChoices) -> String? {
        choices.curlIsAbsent ? "desktop.transition.curlLater" : nil
    }

    static func titleKey(of mode: PageTransition) -> String {
        switch mode {
        case .pageCurl: "desktop.transition.curl"
        case .slide: "desktop.transition.slide"
        case .fastFade: "desktop.transition.fade"
        case .verticalScroll: "desktop.transition.scrollVertical"
        case .horizontalScroll: "desktop.transition.scrollHorizontal"
        }
    }

    private static func reasonKey(of reason: TransitionUnavailability) -> String {
        switch reason {
        case .reduceMotion: "desktop.transition.reason.reduceMotion"
        case .reflowableText: "desktop.transition.reason.text"
        }
    }
}

/// The comic default a series never opened before takes.
///
/// `comic-reader`, *Mode persistence*: a choice applies to the series, a global default to a
/// series never opened, and the comic default is independent of the reflowable one. The
/// per-series half is `ReaderModel.choose`; this is the default half, kept in the same
/// `ShelfMemory` under the fixed-layout scope.
enum MacReadingDefaults {
    static func transition(in preferences: ReaderPreferences) -> PageTransition {
        preferences.themes().default(for: .fixedLayout).transition
    }

    static func setTransition(_ transition: PageTransition, in preferences: ReaderPreferences) {
        let memory = preferences.themes()
        let stored = memory.default(for: .fixedLayout).settingTransition(transition)
        preferences.save(memory.settingDefault(stored, for: .fixedLayout))
    }
}
