public import SwiftUI

/// The display-order step that a reading-order turn of `step` performs.
///
/// Held outside `ReaderView` so a test can call it without building a view. See
/// `turnInReadingOrder(by:)`.
func readingOrderStep(_ step: Int, isRightToLeft: Bool) -> Int {
    isRightToLeft ? -step : step
}

/// The display step a finished horizontal swipe asks for in Fast fade, or 0 for none.
///
/// `page-transitions` "Turning the tap zones off": every other trigger still turns pages,
/// swipe included. A finger that moves left asks for the next display position, as it does
/// in Slide's pager. Right-to-left needs no flip here, because its display order is already
/// reversed. Android's `fadeSwipeStep` is the same rule.
func fadeSwipeStep(travel: Double, threshold: Double = fadeSwipeThreshold) -> Int {
    if travel <= -threshold { return 1 }
    if travel >= threshold { return -1 }
    return 0
}

/// How far a swipe travels, in points, before it turns the page.
let fadeSwipeThreshold = 48.0

// Where a tap lands and what a page turn does.
//
// Split out of `ReaderView.swift`, which had reached the 400-line cap this project
// enforces. The division is not arbitrary: everything here answers "what did the reader
// just ask for", and everything left there answers "what is on screen".

extension EnvironmentValues {
    /// Whether a tap in the leading or trailing third of a page turns it.
    ///
    /// `page-transitions` makes it a setting, and the setting lives on `AppSettings` at
    /// the app layer while the gesture is answered here. An environment value rather than
    /// a parameter threaded through the reader's views, which is what Android's
    /// `LocalTapTurnsPages` is for the same reason.
    ///
    /// True by default: the setting's own default, and the right answer for a preview or
    /// a test that composes the reader with no app above it.
    @Entry public var turnPagesByTappingTheEdges: Bool = true

    /// What a horizontal swipe over a page turns by, or `nil` where the container owns the
    /// swipe itself. Only Fast fade sets it: Slide's pager and the curl bring their own drag.
    @Entry var swipeTurn: SwipeTurn?
}

/// A turn by a display step, handed down to the page. A type rather than a bare closure,
/// the way `OpenPublicationRoute` is, because a closure in the environment is never equal
/// to the last one and invalidates every view that reads it on each update.
struct SwipeTurn {
    let turn: (Int) -> Void

    func callAsFunction(_ step: Int) { turn(step) }
}

extension ReaderView {

    /// What a tap means, by where it landed.
    ///
    /// `comic-reader`: the edges turn pages and do not reveal the chrome, the
    /// centre toggles it. The zones are "mirrored in right-to-left mode" for free
    /// here — the pager's *data* is reversed for RTL, so moving one step to the
    /// right on screen is always one step to the right on screen, whichever way
    /// the story runs.
    func handleTap(at location: CGPoint, in size: CGSize, turns: Bool) {
        let edge = size.width * edgeZoneFraction
        // `page-transitions`: with the zones off "a tap anywhere toggles the chrome, and
        // no tap turns a page". Not "no tap does anything" — the way back to the menu is
        // the one thing a reader still needs from a tap.
        if turns, location.x < edge {
            turnWithTransition(by: -1)
        } else if turns, location.x > size.width - edge {
            turnWithTransition(by: 1)
        } else {
            toggleChrome()
        }
    }

    /// What the Return key does too — `page-transitions` asks for "one key" that
    /// toggles the chrome the same way a centre tap does.
    func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) { wantsChrome.toggle() }
    }

    /// A tap handler with the setting already read into it.
    ///
    /// **The flag is read here, in a body pass, and captured by value.** Read inside the
    /// closure instead, it resolves long after that pass — a gesture recogniser calls it —
    /// and a `@Environment` property read then gives back its *default*, which is `true`.
    /// So the setting did nothing on a device while every test passed, because a test calls
    /// the rule and not the closure. Found by turning the zones off on a simulator and
    /// tapping the side of a page.
    ///
    /// @param rescaling puts a tap in one half of a spread back into the whole spread's
    /// terms. Identity for a single page.
    func tapHandler(
        rescaling: @escaping (CGPoint, CGSize) -> (CGPoint, CGSize) = { ($0, $1) }
    ) -> (CGPoint, CGSize) -> Void {
        let turns = tapTurnsPages
        return { location, size in
            let (point, area) = rescaling(location, size)
            handleTap(at: point, in: area, turns: turns)
        }
    }

    /// The same zones the page's own recognisers use to route a tap.
    var edgeZoneFraction: CGFloat { ZoomablePage.edgeZoneFraction }

    /// Turns by `step` in reading order — "the next page to read" — rather than in the
    /// display order `turn(by:)` takes. Space, Page Up/Down and the volume keys are
    /// non-spatial in this way, unlike the arrow keys and the edge taps, which stay
    /// spatial on purpose (`comic-reader`). Under right-to-left the display order is
    /// reversed (`ReaderNavigation.displayIndex(forModel:)`), so reading order and
    /// display order point opposite ways, and the step has to flip to keep meaning
    /// "next".
    func turnInReadingOrder(by step: Int) {
        turnWithTransition(by: readingOrderStep(step, isRightToLeft: isRightToLeft))
    }

    /// A turn asked for by a tap zone, a key, a controller or VoiceOver, run through the
    /// transition the reader chose.
    ///
    /// Only Curl needs this, and it needs it because its motion lives in the gesture
    /// rather than in the container: Slide's pager animates `displayIndex` and Fast fade
    /// dissolves on it, so for them a turn is already the mode. In Curl the page simply
    /// appeared, which is the one mode the reader picked *for* its motion. Files a
    /// ``CurlRequest`` and lets `CurledPages` roll the page over; `turn(by:)` commits the
    /// page afterwards, from `onTurned`, which is why that path must not file one itself.
    func turnWithTransition(by step: Int) {
        let isForward = readingOrderStep(step, isRightToLeft: isRightToLeft) > 0
        guard CurlRequest.runsCurl(
            mode: model.transitions(reduceMotion: reduceMotion).effective,
            step: step,
            // D10: past the last page the end screen is the destination, and the curl
            // lifts the page off it as it does off any other sheet.
            hasDestination: model.pages.indices.contains(displayIndex + step)
                || CurlRequest.endsAhead(
                    isForward: isForward, page: model.currentIndex, pageCount: model.pages.count
                )
        ) else { return turn(by: step) }
        curlRequest = CurlRequest(isForward: isForward, serial: (curlRequest?.serial ?? 0) + 1)
    }

    /// Commits the turn: the page the reader asked for becomes the page on screen.
    ///
    /// Deliberately never files a ``CurlRequest``. `CurledPages` calls this from
    /// `onTurned`, after it has already rolled the page over, and a request filed here
    /// would roll the same page over again for ever.
    func turn(by step: Int) {
        let next = displayIndex + step
        // `comic-reader`: turning past the last page reaches an end screen rather
        // than nothing. In right-to-left the last *page* is the first display
        // position, which is why this asks the model rather than the pager.
        if !model.pages.indices.contains(next), model.currentIndex == model.pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.2)) { hasReachedEnd = true }
            return
        }
        guard model.pages.indices.contains(next) else {
            // The one page turn that earns a haptic is the one that does not happen.
            // Nothing on screen says the reader is already at the first page — the
            // page simply stays put, which is indistinguishable from a missed tap.
            refusals += 1
            return
        }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : .default) {
            displayIndex = next
        }
    }

    /// Moves the reader to a page it did not reach by turning.
    ///
    /// Separate from ``turn(by:)`` because a jump is the thing `comic-reader` offers a
    /// way back from: "releasing jumps there, with a control to return to the previous
    /// position". Turning a page is not.
    func jump(to index: Int) {
        guard model.pages.indices.contains(index) else { return }
        pageReturn = pageReturn.jumped(from: model.currentIndex, to: index)
        displayIndex = displayIndex(forModel: index)
    }

    /// Goes back to where the reader was before the last jump.
    func returnFromJump() {
        guard let mark = pageReturn.mark, model.pages.indices.contains(mark) else { return }
        pageReturn = pageReturn.taken()
        withAnimation(.easeInOut(duration: 0.2)) {
            displayIndex = displayIndex(forModel: mark)
        }
    }

    /// Restarts the auto-hide countdown whenever either of these changes.
    /// Not `private`: `ReaderView.swift` reads this, and Swift's `private` is file-scoped,
    /// so the split that keeps that file under the line cap is what widens it.
    var chromeTimerKey: String {
        // The strip counts as interaction: reading a row of thumbnails takes longer
        // than four seconds, and the chrome vanishing underneath would take the
        // strip with it.
        // A scrub counts too, and now moves nothing until it is released — without this
        // a slow drag hides the slider under the finger.
        // The menu counts too, and for the strongest version of the same reason: a reader
        // choosing a reading direction has not stopped interacting, and the chrome timing
        // out under the sheet would leave them with no way back to it when the sheet closes.
        "\(isChromeVisible)-\(displayIndex)-\(isBrowsingThumbnails)-\(isAdjusting)"
            + "-\(isShowingMenu)"
            + "-\(scrubbing ?? -1)"
    }
}
