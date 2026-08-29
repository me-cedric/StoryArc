internal import SwiftUI

// Where a tap lands and what a page turn does.
//
// Split out of `ReaderView.swift`, which had reached the 400-line cap this project
// enforces. The division is not arbitrary: everything here answers "what did the reader
// just ask for", and everything left there answers "what is on screen".

extension ReaderView {

    /// What a tap means, by where it landed.
    ///
    /// `comic-reader`: the edges turn pages and do not reveal the chrome, the
    /// centre toggles it. The zones are "mirrored in right-to-left mode" for free
    /// here — the pager's *data* is reversed for RTL, so moving one step to the
    /// right on screen is always one step to the right on screen, whichever way
    /// the story runs.
    func handleTap(at location: CGPoint, in size: CGSize) {
        let edge = size.width * edgeZoneFraction
        if location.x < edge {
            turn(by: -1)
        } else if location.x > size.width - edge {
            turn(by: 1)
        } else {
            withAnimation(.easeInOut(duration: 0.2)) { wantsChrome.toggle() }
        }
    }

    /// The same zones the page's own recognisers use to route a tap.
    var edgeZoneFraction: CGFloat { ZoomablePage.edgeZoneFraction }

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
        "\(isChromeVisible)-\(displayIndex)-\(isBrowsingThumbnails)-\(isAdjusting)"
            + "-\(scrubbing ?? -1)"
    }
}
