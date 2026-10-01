internal import SwiftUI
import Testing
import ReadiumNavigator

@testable import EpubReaderFeature

/// `page-transitions`, *Hardware input*: arrow, page and space keys turn the page, and
/// one key — Return — toggles the chrome. Neither reached the reflowable reader before
/// this; `EpubTurnKey.outcome` is the whole rule, pulled out of the view's key handler
/// so it can be asserted with no key-press event and no simulator.
@Suite("Which key turns the reflowable reader, or toggles its chrome")
struct EpubTurnKeyTests {
    @Test("The left arrow and Page Up turn backward")
    func backward() {
        #expect(EpubTurnKey.outcome(for: .leftArrow) == .backward)
        #expect(EpubTurnKey.outcome(for: .pageUp) == .backward)
    }

    @Test("The right arrow, Page Down and Space turn forward")
    func forward() {
        #expect(EpubTurnKey.outcome(for: .rightArrow) == .forward)
        #expect(EpubTurnKey.outcome(for: .pageDown) == .forward)
        #expect(EpubTurnKey.outcome(for: .space) == .forward)
    }

    @Test("Return toggles the chrome, not a turn")
    func chrome() {
        #expect(EpubTurnKey.outcome(for: .return) == .toggleChrome)
    }

    @Test("An unmapped key does nothing, so typing in a search field is not a turn")
    func unmapped() {
        #expect(EpubTurnKey.outcome(for: "a") == nil)
    }

    /// The key Readium reports while the navigator or its web view holds the first
    /// responder, which is most of the time: the navigator takes it when it appears.
    @Test("A key Readium reports maps the same way")
    func readiumKeys() {
        #expect(EpubTurnKey.outcome(for: KeyEvent(phase: .down, key: .arrowLeft)) == .backward)
        #expect(EpubTurnKey.outcome(for: KeyEvent(phase: .down, key: .pageUp)) == .backward)
        #expect(EpubTurnKey.outcome(for: KeyEvent(phase: .down, key: .arrowRight)) == .forward)
        #expect(EpubTurnKey.outcome(for: KeyEvent(phase: .down, key: .pageDown)) == .forward)
        #expect(EpubTurnKey.outcome(for: KeyEvent(phase: .down, key: .space)) == .forward)
        #expect(EpubTurnKey.outcome(for: KeyEvent(phase: .down, key: .enter)) == .toggleChrome)
        #expect(EpubTurnKey.outcome(for: KeyEvent(phase: .down, key: .a)) == nil)
    }

    @Test("A key with a modifier is a shortcut, not a turn")
    func readiumShortcut() {
        #expect(EpubTurnKey.outcome(for: KeyEvent(phase: .down, key: .arrowRight, modifiers: .command)) == nil)
    }
}
