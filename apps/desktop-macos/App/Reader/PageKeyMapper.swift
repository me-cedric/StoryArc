import Foundation
import StoryArcCore

/// What a key asks the reader to do.
enum PageAction: Sendable, Equatable {
    case next
    case previous
    case first
    case last
    case toggleChrome
}

/// A key a reader can press over a page. Named rather than raw so the mapper is pure.
enum PageKey: Sendable, Equatable {
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case pageUp
    case pageDown
    case space
    case home
    case end
    case `return`
}

/// Keys to page actions, with the reading direction in the answer.
///
/// `desktop-experience`, *Keys that turn pages*: the horizontal keys follow the reading
/// direction, so in a right-to-left publication the right arrow shows the previous page —
/// "the key points the way the page moves" — while Page Down and Space are non-spatial and
/// still show the next page. The same split `ReaderView` makes on iOS between
/// `turnWithTransition` (spatial) and `turnInReadingOrder` (non-spatial). Task 2.11.
enum PageKeyMapper {
    /// - Parameter isEditingText: a text field has focus. *A shortcut while typing*: a letter
    ///   or an arrow then edits the text and turns nothing.
    static func action(
        for key: PageKey,
        direction: ReadingDirection,
        isEditingText: Bool = false
    ) -> PageAction? {
        guard !isEditingText else { return nil }
        let isRightToLeft = direction == .rightToLeft
        switch key {
        case .rightArrow: return isRightToLeft ? .previous : .next
        case .leftArrow: return isRightToLeft ? .next : .previous
        case .pageDown, .space, .downArrow: return .next
        case .pageUp, .upArrow: return .previous
        case .home: return .first
        case .end: return .last
        case .return: return .toggleChrome
        }
    }

    /// The page an action lands on, or `nil` when it moves nothing.
    ///
    /// *A key at the end*: the next-page key on the last page does not move, and nothing is
    /// announced as an error. Opening the next publication is the reader's own offer, not
    /// this mapper's.
    static func destination(of action: PageAction, from index: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let target: Int
        switch action {
        case .next: target = index + 1
        case .previous: target = index - 1
        case .first: target = 0
        case .last: target = count - 1
        case .toggleChrome: return nil
        }
        guard (0..<count).contains(target), target != index else { return nil }
        return target
    }
}
