internal import UIKit

internal import ReadiumNavigator
internal import StoryArcCore

// The finger drives the curl over prose. Task 8.12 of `close-the-audited-gaps`, owner answer O1.
//
// `page-transitions` says the curl "SHALL be driven by the finger, not by a timeline", and the
// EPUB curl ran a fixed 340 ms roll after a tap, a key or a released swipe. Now a drag lifts the
// page and the fold follows the finger. The release follows the comic reader's rule,
// `CurlTurn`, with its thresholds and its spring, and a drag that catches a settle takes it
// over from where the page is drawn. A tap, a key or a controller still turns the page: it
// runs the same spring from 0 to a whole turn, as the comic reader's `CurlRequest` does.

/// One phase of a finger on the page, as the page's pan recogniser reports it, in points.
enum ProseDrag: Equatable {
    case began(travel: Double)
    case changed(travel: Double)
    case ended(travel: Double, velocity: Double)
}

/// The arithmetic of one prose turn, apart from the views, so it can be asserted.
///
/// A comic page has both neighbours as rasters before the finger lands, so its drag can swing
/// from a turn forward to a turn back. A page of prose has neither until the navigator moves,
/// and the navigator moves one way. So the first sideways travel picks the direction, and the
/// drag is clamped to it: a finger that comes back past where it started holds the page flat,
/// and a release there springs it back.
struct ProseCurl: Equatable {
    let isForward: Bool
    let isRightToLeft: Bool

    /// The turn a drag starts, from the travel that made the recogniser fire, or `nil` for a
    /// drag with no sideways travel yet.
    static func starting(travel: Double, isRightToLeft: Bool) -> ProseCurl? {
        let forward = CurlTurn.forward(travel: travel, isRightToLeft: isRightToLeft)
        guard forward != 0 else { return nil }
        return ProseCurl(isForward: forward > 0, isRightToLeft: isRightToLeft)
    }

    /// Where the page stands after `travel` points from `base`, in this turn's direction only.
    func progress(base: Double, travel: Double, width: Double) -> Double {
        CurlTurn.progress(
            base: base,
            travel: travel,
            width: width,
            isRightToLeft: isRightToLeft,
            canTurnBack: !isForward,
            canTurnForward: isForward
        )
    }

    /// Where a released page springs to: a whole turn, or flat again.
    ///
    /// - Parameter velocity: the finger's horizontal speed in points per second.
    func target(reached: Double, velocity: Double) -> Double {
        let flick = CurlTurn.forward(
            travel: CurlTurn.predictedTravel(velocity: velocity), isRightToLeft: isRightToLeft
        )
        let settles = CurlTurn.settles(
            progress: reached,
            isFlick: CurlTurn.flicks(velocity: flick, progress: reached)
        )
        return settles ? whole : 0
    }

    /// A whole turn in this direction, which is also where a tap or a key springs to.
    var whole: Double { isForward ? 1 : -1 }
}

/// Runs prose turns: the lift when a turn starts, the finger, the spring, and the put-back.
///
/// One per reader. A turn holds a sheet over the navigator from its first move until its
/// spring lands, and the navigator has moved under that sheet by then. A turn that springs
/// back moves the navigator back under the sheet before the sheet comes off, so the reader is
/// on the page they started from and the sheet never shows a page that is not there.
@MainActor
final class ProseCurlDriver {
    private var overlay: CurlOverlay?
    private var turn: ProseCurl?
    /// The navigator's move under the sheet, and whether the page changed.
    private var move: Task<Bool, Never>?
    private var base = 0.0
    private var origin = 0.0
    private var reached = 0.0
    private var isDragging = false
    /// While the navigator goes back under a sheet that sprang back, nothing takes the page.
    private var isClosing = false
    /// Bumped by every drag and every spring, so a spring a drag took over leaves the turn
    /// alone when its completion runs.
    private var ticket = 0

    /// Whether a sheet is over the page. A test reads it; the reader never needs to.
    var isTurning: Bool { overlay != nil }

    func drag(_ phase: ProseDrag, on navigator: EPUBNavigatorViewController, isRightToLeft: Bool) {
        switch phase {
        case .began(let travel):
            guard !isClosing else { return }
            ticket &+= 1
            if let overlay {
                // A settle still running is caught where it is drawn.
                base = overlay.drawn
                overlay.follow(base)
            } else {
                guard let turn = ProseCurl.starting(travel: travel, isRightToLeft: isRightToLeft),
                      lift(turn, on: navigator)
                else { return }
                base = 0
            }
            origin = travel
            reached = base
            isDragging = true
        case .changed(let travel):
            guard isDragging, let turn, let overlay else { return }
            reached = turn.progress(base: base, travel: travel - origin, width: overlay.width)
            overlay.follow(reached)
        case .ended(_, let velocity):
            guard isDragging else { return }
            isDragging = false
            guard let turn else { return }
            Task { await settle(to: turn.target(reached: reached, velocity: velocity), on: navigator) }
        }
    }

    /// A tap, a key or a controller: the same spring a released drag runs, from flat to whole.
    ///
    /// - Returns: false when no sheet could be raised, so the caller turns the page plainly.
    @discardableResult
    func request(forward: Bool, on navigator: EPUBNavigatorViewController, isRightToLeft: Bool) async -> Bool {
        // A finger on the page or a turn in flight outranks the press, as in the comic reader.
        guard !isDragging, overlay == nil else { return true }
        let turn = ProseCurl(isForward: forward, isRightToLeft: isRightToLeft)
        guard lift(turn, on: navigator) else { return false }
        ticket &+= 1
        await settle(to: turn.whole, on: navigator)
        return true
    }

    /// Raises the sheet over the page and starts the navigator's move under it.
    ///
    /// The order is the whole trick: the leaving page is rastered while it is on screen; at a
    /// chapter end the arriving page is rastered too, where Readium already holds it
    /// (``ProsePages``); the sheet goes up flat and whole, so it looks like the page under it;
    /// then the navigator moves with no animation of its own. Inside a chapter the arriving
    /// page is rastered once the move lands, which measured under one frame.
    ///
    /// The sheet is added to the navigator view's superview, not to the navigator view: the
    /// raster after the move is of the navigator, and a sheet inside it would be in it.
    private func lift(_ turn: ProseCurl, on navigator: EPUBNavigatorViewController) -> Bool {
        guard let page = navigator.view, let host = page.superview,
              let outgoing = page.raster(afterScreenUpdates: false)
        else { return false }
        let ahead = ProsePages.ahead(in: page, forward: turn.isForward, isRightToLeft: turn.isRightToLeft)
        let overlay = CurlOverlay(
            page: outgoing, other: ahead, isRightToLeft: turn.isRightToLeft, scale: page.rasterScale
        )
        overlay.view.frame = page.frame
        host.addSubview(overlay.view)
        self.overlay = overlay
        self.turn = turn

        let move = Task { @MainActor in
            let options = NavigatorGoOptions(animated: false)
            let moved = turn.isForward
                ? await navigator.goForward(options: options)
                : await navigator.goBackward(options: options)
            // Taken even when one was rastered ahead: it is the page that actually arrived.
            if moved, let incoming = page.raster(afterScreenUpdates: true) { overlay.other = incoming }
            return moved
        }
        self.move = move
        Task {
            // The first or the last page of the book: nothing to turn to, so the sheet goes at
            // once rather than rolling onto the page it started from.
            if await !move.value, self.overlay === overlay { close() }
        }
        return true
    }

    /// Springs the page to `target`, then leaves the reader on the page the spring chose.
    private func settle(to target: Double, on navigator: EPUBNavigatorViewController) async {
        guard let overlay, let turn else { return }
        ticket &+= 1
        let mine = ticket
        await overlay.settle(to: target)
        guard mine == ticket, self.overlay === overlay else { return }
        isClosing = true
        let moved = await move?.value ?? false
        if target == 0, moved {
            let options = NavigatorGoOptions(animated: false)
            _ = turn.isForward
                ? await navigator.goBackward(options: options)
                : await navigator.goForward(options: options)
        }
        close()
    }

    private func close() {
        overlay?.view.removeFromSuperview()
        overlay = nil
        turn = nil
        move = nil
        isDragging = false
        isClosing = false
    }
}

extension EpubReaderModel {
    /// Turns a page by rolling a picture of it off a picture of the next one, from a tap, a
    /// key or a controller. A page that cannot be rastered turns plainly, which costs the
    /// transition and never the turn.
    func turnWithCurl(forward: Bool) async {
        guard let navigator,
              await proseCurl.request(forward: forward, on: navigator, isRightToLeft: isRightToLeft)
        else {
            if forward { await goForward() } else { await goBackward() }
            return
        }
    }

    /// A finger on the page while Curl draws the turn.
    func curlDrag(_ phase: ProseDrag) {
        guard let navigator else { return }
        proseCurl.drag(phase, on: navigator, isRightToLeft: isRightToLeft)
    }
}
