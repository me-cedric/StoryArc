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
}
