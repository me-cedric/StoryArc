import Foundation
import GameController
import Testing

@testable import EpubReaderFeature

/// `page-transitions`, *Hardware input*: a game controller turns the reflowable reader's
/// page "with the current transition applied". The comic reader's own
/// `GameControllerTurningTests` asserts the same binding in the other package.
@Suite("A game controller turns the reflowable reader")
struct EpubGameControllerTests {

    @Test("The d-pad and the shoulders turn the way they point; a release is not a press")
    @MainActor
    func bindAndUnbind() throws {
        let controller = GCController.withExtendedGamepad()
        var turns: [Bool] = []
        EpubGameControllerTurning.bind(controller, to: { turns.append($0) })
        let gamepad = try #require(controller.extendedGamepad)
        let right = try #require(gamepad.dpad.right.pressedChangedHandler)
        let left = try #require(gamepad.dpad.left.pressedChangedHandler)
        let rightShoulder = try #require(gamepad.rightShoulder.pressedChangedHandler)
        let leftShoulder = try #require(gamepad.leftShoulder.pressedChangedHandler)
        right(gamepad.dpad.right, 1, true)
        left(gamepad.dpad.left, 1, true)
        rightShoulder(gamepad.rightShoulder, 1, true)
        leftShoulder(gamepad.leftShoulder, 1, true)
        right(gamepad.dpad.right, 0, false)
        #expect(turns == [true, false, true, false])

        EpubGameControllerTurning.unbind(controller)
        #expect(gamepad.dpad.right.pressedChangedHandler == nil)
        #expect(gamepad.leftShoulder.pressedChangedHandler == nil)
    }

    /// A controller is bound once, when the reader appears. A turn closure captured then
    /// kept the mode the book opened in, so choosing Fast fade later still slid the page.
    @Test("The turn is decided when the button is pressed, not when the reader appeared")
    func theModeIsReadAtThePress() throws {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        let view = try String(
            contentsOf: directory.appending(path: "Sources/EpubReaderFeature/EpubReaderView.swift"),
            encoding: .utf8
        )

        #expect(view.contains("onTurn: { forward in Task { await model.turn(forward: forward) } }"))
    }
}
