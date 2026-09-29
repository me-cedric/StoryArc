import GameController
import Testing

@testable import ReaderFeature

/// Which way a d-pad or shoulder press turns. `GameControllerTurning` is the untestable
/// half — nothing on the host simulates a `GCController` — so this is the whole of what
/// can be asserted about "iOS reads no game controller".
@Suite("Game controller turning")
struct GameControllerTurningTests {

    @Test("The d-pad turns the same way its arrow points")
    func dpadIsSpatial() {
        #expect(GameControllerTurn.step(for: .dpadLeft) == -1)
        #expect(GameControllerTurn.step(for: .dpadRight) == 1)
    }

    @Test("A shoulder button turns the same way as the d-pad on its side")
    func shouldersMatchTheirSide() {
        #expect(GameControllerTurn.step(for: .leftShoulder) == GameControllerTurn.step(for: .dpadLeft))
        #expect(GameControllerTurn.step(for: .rightShoulder) == GameControllerTurn.step(for: .dpadRight))
    }

    @Test("A bound controller's buttons turn; an unbound one's do not")
    @MainActor
    func bindAndUnbind() {
        let controller = GCController.withExtendedGamepad()
        var turns: [Int] = []
        GameControllerTurning.bind(controller, to: { turns.append($0) })
        let gamepad = controller.extendedGamepad
        #expect(gamepad?.dpad.right.pressedChangedHandler != nil)
        gamepad?.dpad.right.pressedChangedHandler?(gamepad!.dpad.right, 1, true)
        gamepad?.leftShoulder.pressedChangedHandler?(gamepad!.leftShoulder, 1, true)
        // A release is not a second press.
        gamepad?.dpad.right.pressedChangedHandler?(gamepad!.dpad.right, 0, false)
        #expect(turns == [1, -1])

        GameControllerTurning.unbind(controller)
        #expect(gamepad?.dpad.left.pressedChangedHandler == nil)
        #expect(gamepad?.dpad.right.pressedChangedHandler == nil)
        #expect(gamepad?.leftShoulder.pressedChangedHandler == nil)
        #expect(gamepad?.rightShoulder.pressedChangedHandler == nil)
    }
}
