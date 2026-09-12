internal import SwiftUI

internal import StoryArcCore

// Which containers a change of displayed index opens a frame run over.
//
// `page-transitions`'s *Frame budget* covers "any transition", and the instrument reached
// one of them: `CurledPages` opens a run when the finger takes the page and closes it when
// the settle completes. Slide and Fast fade animate a turn too, and neither has a finger to
// bound a run with, so the index they draw bounds it instead.
//
// Android's `TurnProbe.kt` is the twin, rule for rule.
extension PageTransition {

    /// How long a run opened by a change of displayed index stays open, or `nil` where a
    /// change of index bounds no run.
    ///
    /// Curl is `nil` because the curl counts its own frames already, from the first pixel of
    /// the drag to the end of the settle. Its index moves *after* the turn, so a run opened
    /// there would count the frames that follow a turn instead of the frames of one.
    ///
    /// Both scroll modes are `nil` because a scroll has no discrete turn to bound a run.
    /// The spec's own table says so — Scroll is "continuous scrolling, no discrete turn" —
    /// and its index moves on every frame of a drag, so each move would open a run that the
    /// next move closes and the numbers would describe the reader's finger.
    var turnWindow: Double? {
        switch self {
        case .slide, .fastFade: FrameProbe.turnWindow
        case .pageCurl, .verticalScroll, .horizontalScroll: nil
        }
    }
}

extension View {

    /// Counts the frames of a turn this container animates but reports no end for.
    ///
    /// Costs one `onChange` and one comparison per turn where the mode bounds no run, and
    /// nothing at all in a shipping build, where `FrameProbe.isArmed` is false.
    func probingTurns(_ index: Int, of mode: PageTransition) -> some View {
        onChange(of: index) { _, _ in
            guard let window = mode.turnWindow else { return }
            FrameProbe.turned(over: window)
        }
    }
}
