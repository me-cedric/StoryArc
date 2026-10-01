internal import SwiftUI
internal import GameController
internal import ReadiumNavigator

// Keyboard, Return and a game controller for the reflowable reader.
//
// `page-transitions`, *Hardware input*: arrow, page and space keys turn the page in
// every reader, and a game controller's d-pad and shoulder buttons do the same. No key
// toggled the chrome in any reader before this; Return does it here and is the "one key"
// `native-experience` asks every reader to bind.
//
// A key reaches the reader by one of two ways. While the navigator or its web view holds
// the first responder, Readium's key observer hears it — see ``TurnGestures``. While
// SwiftUI holds the focus, after a sheet closes, `EpubReaderTurnKeys` below hears it.
// Only one of them holds the first responder at a time, so a key turns one page.
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

    /// The same rule for a key Readium reports. A key with a modifier is a shortcut, not a
    /// turn, as Readium's own `DirectionalNavigationAdapter` decides.
    static func outcome(for event: KeyEvent) -> EpubTurnKey? {
        guard event.modifiers.isEmpty else { return nil }
        switch event.key {
        case .arrowLeft, .pageUp: return .backward
        case .arrowRight, .pageDown, .space: return .forward
        case .enter: return .toggleChrome
        default: return nil
        }
    }
}

extension EpubReaderModel {
    /// The turn a key or a controller takes, decided when it is pressed: Fast fade's own
    /// where it owns the turn, Readium's otherwise.
    ///
    /// Decided here rather than captured by the view, because a controller is bound once,
    /// when the reader appears. A closure captured then kept the mode the book opened in,
    /// so a reader who chose Fast fade afterwards still got a Slide from the d-pad.
    func turn(forward: Bool) async {
        if ownsTheTurn {
            await turnWithFade(forward: forward)
        } else if forward {
            await goForward()
        } else {
            await goBackward()
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
                guard press.modifiers.isEmpty else { return .ignored }
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
