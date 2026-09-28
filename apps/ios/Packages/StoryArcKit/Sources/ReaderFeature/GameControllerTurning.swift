internal import GameController
internal import SwiftUI

/// Which control a press came from. The d-pad and the shoulder buttons are the four
/// `comic-reader` names for "hardware input (external controller)".
enum GameControllerButton {
    case dpadLeft, dpadRight, leftShoulder, rightShoulder
}

/// Where a controller press turns to.
///
/// All four map to `turn(by:)` — the same spatial step the arrow keys and the edge
/// taps already use, not the reading-order step Space and the page keys take. A d-pad
/// and a shoulder button are directional controls on the case in the reader's hands,
/// the same way an arrow key is a directional key on the keyboard in front of them.
/// A plain enum, so `GameControllerTurningTests` can drive it with no controller
/// hardware at all — the same reason `EarlyPageTallness` is split out.
enum GameControllerTurn {
    static func step(for button: GameControllerButton) -> Int {
        switch button {
        case .dpadLeft, .leftShoulder: -1
        case .dpadRight, .rightShoulder: 1
        }
    }
}

/// Binds a comic's turn to whichever game controller is current, and to the next one
/// that connects.
///
/// `comic-reader`: "iOS reads no game controller" — SwiftUI's key presses do not carry
/// a gamepad's buttons, so a d-pad or a shoulder press on a paired controller did
/// nothing. Untestable on the host — nothing here simulates a `GCController` — so the
/// mapping this binds is what `GameControllerTurningTests` actually asserts.
struct GameControllerTurning: ViewModifier {
    let onTurn: (Int) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { bind(GCController.current) }
            .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) {
                bind($0.object as? GCController)
            }
    }

    private func bind(_ controller: GCController?) {
        guard let gamepad = controller?.extendedGamepad else { return }
        gamepad.dpad.left.pressedChangedHandler = { _, _, pressed in
            if pressed { onTurn(GameControllerTurn.step(for: .dpadLeft)) }
        }
        gamepad.dpad.right.pressedChangedHandler = { _, _, pressed in
            if pressed { onTurn(GameControllerTurn.step(for: .dpadRight)) }
        }
        gamepad.leftShoulder.pressedChangedHandler = { _, _, pressed in
            if pressed { onTurn(GameControllerTurn.step(for: .leftShoulder)) }
        }
        gamepad.rightShoulder.pressedChangedHandler = { _, _, pressed in
            if pressed { onTurn(GameControllerTurn.step(for: .rightShoulder)) }
        }
    }
}
