import CoreGraphics

/// Whether a drag across a page commits a turn, and which way.
///
/// `desktop-experience`, *Dragging to turn a page*: past the distance that commits a turn the
/// page turns in the direction of the drag, mirrored right-to-left; short of it the page
/// settles back and no turn is counted. The curl is wave 5, so in wave 2 the sheet slides
/// with the pointer. Task 2.15.
enum DragTurn {
    /// The least a drag travels, in points, before it commits: the iOS swipe's 48 on a
    /// narrow page, and a sixth of the page on a wide one so a flick on a 27-inch display
    /// is a gesture rather than a twitch.
    static let minimumTravel: CGFloat = 48
    static let travelFraction: CGFloat = 1.0 / 6.0

    static func threshold(width: CGFloat) -> CGFloat {
        max(minimumTravel, width * travelFraction)
    }

    /// The page step a finished drag asks for, or 0 for none.
    ///
    /// A drag to the left reveals what sits to the right: the next page left-to-right and
    /// the previous page right-to-left, exactly as the trailing click zone does.
    static func step(translation: CGFloat, width: CGFloat, isRightToLeft: Bool) -> Int {
        let limit = threshold(width: width)
        let display: Int
        if translation <= -limit {
            display = 1
        } else if translation >= limit {
            display = -1
        } else {
            return 0
        }
        return isRightToLeft ? -display : display
    }

    /// How far the sheet has slid, 0 to 1, for the slide while the pointer is down.
    static func progress(translation: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(1, abs(translation) / width)
    }
}
