internal import SwiftUI
internal import GameController

// Keyboard, Return and a game controller for the reflowable reader.
//
// `page-transitions`, *Hardware input*: arrow, page and space keys turn the page in
// every reader, and a game controller's d-pad and shoulder buttons do the same —
// `EpubReaderHost.swift` already does the equivalent for an edge tap. No key toggles
// the chrome in any reader before this; Return does it here and is the "one key"
// `page-transitions` asks every reader to bind.
//
// Split out of `EpubReaderView.swift`, which is at the 400-line cap SwiftLint enforces
// under `apps/ios`, the same reason the comic reader keeps `ReaderKeyboardFocus.swift`
// and `GameControllerTurning.swift` apart from `ReaderView.swift`. This package cannot
// depend on `ReaderFeature` to reuse those — "no feature depends on another feature
// module" — so the two small pieces below mirror them instead.

/// Which key, if any, this press turns the page with or toggles the chrome with.
///
/// A plain enum over `KeyEquivalent`, so the mapping is testable with no view and no
/// key-press event at all — the same reason `TurnDrag.direction` on Android is pulled
/// out of its gesture handler.
enum EpubTurnKey: Equatable {
    case forward, backward, toggleChrome

    static func outcome(for key: KeyEquivalent) -> EpubTurnKey? {
        switch key {
        case .leftArrow, .pageUp: .backward
        case .rightArrow, .pageDown, .space: .forward
        case .return: .toggleChrome
        default: nil
        }
    }
}

/// Binds the turn keys, Return, and keyboard focus itself.
///
/// `.focusable()` alone offers to become the first responder; nothing claims it until
/// `ReaderKeyboardFocus`'s own note applies here too — a sheet becomes the focused view
/// while it is up, and dismissing it does not hand focus back.
struct EpubReaderTurnKeys: ViewModifier {
    let isCoveredBySheet: Bool
    let onTurn: (Bool) -> Void
    let onToggleChrome: () -> Void

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onAppear { isFocused = true }
            .onChange(of: isCoveredBySheet) { _, isCovered in if !isCovered { isFocused = true } }
            .onKeyPress { press in
                switch EpubTurnKey.outcome(for: press.key) {
                case .forward: onTurn(true)
                case .backward: onTurn(false)
                case .toggleChrome: onToggleChrome()
                case nil: return .ignored
                }
                return .handled
            }
            .modifier(EpubGameControllerTurning(onTurn: onTurn))
    }
}

/// Binds the reader's turn to whichever game controller is current, and to the next
/// one that connects. `page-transitions`: "iOS reads no game controller" — SwiftUI's
/// key presses do not carry a gamepad's buttons.
struct EpubGameControllerTurning: ViewModifier {
    let onTurn: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            // Every controller already paired, not only `GCController.current`.
            .onAppear { GCController.controllers().forEach { Self.bind($0, to: onTurn) } }
            .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) {
                Self.bind($0.object as? GCController, to: onTurn)
            }
            .onDisappear { GCController.controllers().forEach(Self.unbind) }
    }

    /// Each turning control, paired with whether it turns forward.
    private static func turningButtons(of gamepad: GCExtendedGamepad) -> [(GCControllerButtonInput, Bool)] {
        [
            (gamepad.dpad.left, false), (gamepad.leftShoulder, false),
            (gamepad.dpad.right, true), (gamepad.rightShoulder, true),
        ]
    }

    static func bind(_ controller: GCController?, to onTurn: @escaping (Bool) -> Void) {
        guard let gamepad = controller?.extendedGamepad else { return }
        for (input, forward) in turningButtons(of: gamepad) {
            input.pressedChangedHandler = { _, _, pressed in if pressed { onTurn(forward) } }
        }
    }

    static func unbind(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        for (input, _) in turningButtons(of: gamepad) { input.pressedChangedHandler = nil }
    }
}
