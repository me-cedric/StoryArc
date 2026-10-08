internal import SwiftUI

/// Where a finger on the A to Z rail is, and which letter that is.
///
/// `close-the-audited-gaps` 24.6, decision O23: the rail is **one control**, as the system's
/// own section index is. A tap or a drag selects the letter under the finger, and a letter
/// is chosen once when the finger arrives on it rather than on every point of the drag.
///
/// Pure and free of gestures so `LibraryRailTests` can drag a finger down the whole rail and
/// read off the letters in the order they were chosen. Android's `RailScrub` is the twin.
struct RailScrub: Equatable {

    /// The index of the letter the finger is on, or `nil` while no finger is down.
    private(set) var current: Int?

    /// The letter at a height along the rail, counted over **every** entry.
    ///
    /// - Parameters:
    ///   - y: the finger's height, from the top of the rail's hit region.
    ///   - height: the hit region's height, padding included.
    ///   - inset: the padding above the first letter and below the last, which a finger can
    ///     land on and which counts as the first and the last letter.
    ///   - count: how many entries the shelf offers, drawn or not.
    /// - Returns: `nil` when there is nothing to choose.
    static func index(at y: CGFloat, height: CGFloat, inset: CGFloat, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let span = height - 2 * inset
        guard span > 0 else { return 0 }
        let fraction = (y - inset) / span
        return min(count - 1, max(0, Int((fraction * CGFloat(count)).rounded(.down))))
    }

    /// Moves the finger. Answers the letter it has just arrived on, and `nil` while it stays
    /// on the same one — which is what makes the haptic and the jump fire once a letter.
    mutating func move(to y: CGFloat, height: CGFloat, inset: CGFloat, count: Int) -> Int? {
        guard let next = Self.index(at: y, height: height, inset: inset, count: count),
              next != current
        else { return nil }
        current = next
        return next
    }

    /// The finger lifts. The next touch on the same letter chooses it again.
    mutating func end() {
        current = nil
    }

    /// One step of the VoiceOver adjustable action, from the letter last chosen.
    ///
    /// Clamped at both ends rather than wrapping: Z is not next to A, and a swipe that
    /// wrapped would throw a reader across the whole shelf.
    static func step(from current: Int?, by delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let current else { return delta > 0 ? 0 : count - 1 }
        return min(count - 1, max(0, current + delta))
    }
}
