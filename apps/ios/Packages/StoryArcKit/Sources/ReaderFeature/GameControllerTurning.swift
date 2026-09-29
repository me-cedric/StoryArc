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
            // Every controller already paired, not only `GCController.current`: that is the
            // one used most recently, and a controller paired before the reader opened but
            // not yet pressed is not current.
            .onAppear { GCController.controllers().forEach { Self.bind($0, to: onTurn) } }
            .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) {
                Self.bind($0.object as? GCController, to: onTurn)
            }
            // A handler left bound after the reader closes keeps turning a reader that is
            // gone, and keeps it alive.
            .onDisappear { GCController.controllers().forEach(Self.unbind) }
    }

    /// Each turning control on `gamepad`, and which of the four it is.
    private static func turningButtons(
        of gamepad: GCExtendedGamepad
    ) -> [(GCControllerButtonInput, GameControllerButton)] {
        [
            (gamepad.dpad.left, .dpadLeft),
            (gamepad.dpad.right, .dpadRight),
            (gamepad.leftShoulder, .leftShoulder),
            (gamepad.rightShoulder, .rightShoulder),
        ]
    }

    /// Makes `controller`'s d-pad and shoulders call `onTurn`. Not `private`, so
    /// `GameControllerTurningTests` can bind a virtual controller.
    static func bind(_ controller: GCController?, to onTurn: @escaping (Int) -> Void) {
        guard let gamepad = controller?.extendedGamepad else { return }
        for (input, button) in turningButtons(of: gamepad) {
            input.pressedChangedHandler = { _, _, pressed in
                if pressed { onTurn(GameControllerTurn.step(for: button)) }
            }
        }
    }

    /// Takes the reader's handlers off `controller` again.
    static func unbind(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        for (input, _) in turningButtons(of: gamepad) { input.pressedChangedHandler = nil }
    }
}
