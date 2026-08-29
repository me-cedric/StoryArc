public import Foundation

/// Where the reader was before the last jump, so they can get back to it.
///
/// `comic-reader`, on the page slider: "releasing jumps there, with a control to
/// return to the previous position". A jump is the one movement in the reader that
/// loses a place without being asked to — a page turn goes one step and can be
/// undone by turning back, but a drag from page 4 to page 180 leaves nothing behind.
/// So a jump drops a mark, and the mark is what the control offers.
///
/// One mark, not a stack: the requirement says *the* previous position, and a reader
/// who scrubbed three times in a row wants the place they were reading, which is
/// where the last jump started from.
///
/// A value rather than an object, like the rest of the reader's state: the view holds
/// it and replaces it, and there is nothing here that a test needs a screen to reach.
/// Android's `PageReturn` is the same type.
public struct PageReturn: Sendable, Equatable {
    /// The page to go back to, or `nil` when there is nowhere to go back to.
    public let mark: Int?

    public init(mark: Int? = nil) {
        self.mark = mark
    }

    /// Records a jump, so `origin` becomes what the control offers.
    ///
    /// A move of one page leaves no mark, and neither does a move of none. One page is
    /// a *turn* however it was asked for — a slider nudged by a step, VoiceOver's
    /// increment — and a turn is undone by turning back, which is a thing the reader
    /// can already do. Offering a way back to the page next door would put a control on
    /// screen for every step a VoiceOver reader takes across the slider.
    public func jumped(from origin: Int, to target: Int) -> PageReturn {
        abs(target - origin) <= 1 ? self : PageReturn(mark: origin)
    }

    /// Notes ordinary movement — a turn, a tap, a key.
    ///
    /// Reaching the mark by reading clears it. The offer is to go back to where you
    /// were, and once you are there again the offer is a trip to the current page.
    public func moved(to index: Int) -> PageReturn {
        mark == index ? PageReturn() : self
    }

    /// Spends the mark. The caller moves; this only stops offering.
    public func taken() -> PageReturn {
        PageReturn()
    }
}
