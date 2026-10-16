import StoryArcCore
import Testing

@testable import StoryArc

/// The key mapper of task 2.11: mirrored arrows, non-spatial Space and Page Down, a key
/// at the end, and a text field in focus.
@Suite("Page key mapper")
struct PageKeyMapperTests {
    @Test("Left-to-right: right arrow, Page Down and Space show the next page; left and Page Up the previous")
    func leftToRight() {
        #expect(PageKeyMapper.action(for: .rightArrow, direction: .leftToRight) == .next)
        #expect(PageKeyMapper.action(for: .pageDown, direction: .leftToRight) == .next)
        #expect(PageKeyMapper.action(for: .space, direction: .leftToRight) == .next)
        #expect(PageKeyMapper.action(for: .leftArrow, direction: .leftToRight) == .previous)
        #expect(PageKeyMapper.action(for: .pageUp, direction: .leftToRight) == .previous)
    }

    @Test("Right-to-left: the right arrow shows the previous page, Page Down and Space still the next")
    func rightToLeft() {
        #expect(PageKeyMapper.action(for: .rightArrow, direction: .rightToLeft) == .previous)
        #expect(PageKeyMapper.action(for: .leftArrow, direction: .rightToLeft) == .next)
        #expect(PageKeyMapper.action(for: .pageDown, direction: .rightToLeft) == .next)
        #expect(PageKeyMapper.action(for: .space, direction: .rightToLeft) == .next)
    }

    @Test("Home and End reach the ends, Return toggles the chrome")
    func homeEndReturn() {
        #expect(PageKeyMapper.action(for: .home, direction: .leftToRight) == .first)
        #expect(PageKeyMapper.action(for: .end, direction: .rightToLeft) == .last)
        #expect(PageKeyMapper.action(for: .return, direction: .leftToRight) == .toggleChrome)
    }

    @Test("A key at the end moves nothing and names no error")
    func keyAtTheEnd() {
        #expect(PageKeyMapper.destination(of: .next, from: 11, count: 12) == nil)
        #expect(PageKeyMapper.destination(of: .previous, from: 0, count: 12) == nil)
        #expect(PageKeyMapper.destination(of: .last, from: 11, count: 12) == nil)
        #expect(PageKeyMapper.destination(of: .next, from: 0, count: 0) == nil)
        #expect(PageKeyMapper.destination(of: .next, from: 3, count: 12) == 4)
        #expect(PageKeyMapper.destination(of: .last, from: 3, count: 12) == 11)
        #expect(PageKeyMapper.destination(of: .first, from: 3, count: 12) == 0)
    }

    @Test("With a text field in focus a key edits the text and turns no page")
    func textFieldInFocus() {
        for key in [PageKey.leftArrow, .rightArrow, .space, .pageDown, .home, .end, .return] {
            #expect(PageKeyMapper.action(for: key, direction: .leftToRight, isEditingText: true) == nil)
        }
    }
}
