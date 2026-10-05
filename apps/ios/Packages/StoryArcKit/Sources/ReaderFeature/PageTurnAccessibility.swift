internal import SwiftUI

/// The sentence a turn lands on, for a screen reader.
///
/// `reader.pageLabel` is already what each page answers to VoiceOver, so the announcement and
/// the page say the same thing. `comic-reader` states a fixed-page position as a number and a
/// total; one position, phrased one way.
///
/// Free of `ReaderView` so a host test can read it without building a view: `swift test`
/// cannot put a SwiftUI hierarchy in front of VoiceOver, and the sentence is the part a test
/// can hold to.
func readerPositionSentence(page: Int, of count: Int) -> String {
    String(localized: "reader.pageLabel \(page) \(count)", bundle: .module, locale: .storyArc)
}

/// A named page turn, and the position the turn arrived at.
///
/// `native-experience`, *Screen reader*: "the reader announces the page number and total on
/// each turn, and offers gestures to turn pages". Neither held. A `TabView` contributes the
/// system's own paging gesture, which names a direction on screen rather than a page, and Fast
/// fade is not a pager at all, so that mode offered nothing. No turn was ever announced.
///
/// **The announcement hangs off the position, not off each turn site.** The page moves from a
/// tap zone, an arrow key, a game controller, a swipe and now these two actions, and a path
/// nobody wired would give a silence indistinguishable from the rest working. Reading the page
/// the reader is on makes every path announce by construction.
///
/// Applied to the container every transition mode is built in (`ReaderPages.swift`), so Slide,
/// Curl, Fast fade and both scrolls carry it. SwiftUI hands an accessibility modifier on a
/// container down to the elements inside it, which is how the page itself ends up offering the
/// two actions — the same propagation the right-to-left label beside it relies on.
struct PageTurnAccessibility: ViewModifier {
    /// Where the reader is, already in words. A change to it is a turn, whatever caused it.
    let position: String
    let onNext: () -> Void
    let onPrevious: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: Text("reader.turn.next", bundle: .module)) { onNext() }
            .accessibilityAction(named: Text("reader.turn.previous", bundle: .module)) { onPrevious() }
            .onChange(of: position) { _, arrived in
                AccessibilityNotification.Announcement(arrived).post()
            }
    }
}
