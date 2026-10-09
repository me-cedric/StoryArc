import Testing
import UIKit

@testable import EpubReaderFeature

/// Task 25.6: a long press on the thumb of a theme slider resets the axis, as a long press on
/// the track already did.
@MainActor
@Suite("A long press on a slider resets its axis")
struct SliderLongPressTests {

    private func lift(
        from start: CGPoint,
        to end: CGPoint
    ) -> Int {
        var resets = 0
        let coordinator = SliderLongPress.Coordinator()
        coordinator.action = { resets += 1 }
        coordinator.handle(.began, at: start)
        coordinator.handle(.ended, at: end)
        return resets
    }

    @Test("A press that stays put resets the axis once, when the finger lifts")
    func aStillPressResets() {
        #expect(lift(from: CGPoint(x: 50, y: 20), to: CGPoint(x: 53, y: 22)) == 1)
    }

    @Test("A press that became a drag resets nothing")
    func aDragResetsNothing() {
        #expect(lift(from: CGPoint(x: 50, y: 20), to: CGPoint(x: 120, y: 20)) == 0)
    }

    @Test("The recogniser lands on the slider drawn under it, and on no neighbour")
    func attachesToTheSliderUnderIt() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let above = UISlider(frame: CGRect(x: 0, y: 0, width: 320, height: 40))
        let below = UISlider(frame: CGRect(x: 0, y: 100, width: 320, height: 40))
        let finder = SliderLongPress.Finder(frame: below.frame)
        let coordinator = SliderLongPress.Coordinator()
        finder.coordinator = coordinator
        defer { withExtendedLifetime(coordinator) {} }
        for view in [above, below, finder] { window.addSubview(view) }
        window.makeKeyAndVisible()

        finder.layoutIfNeeded()
        finder.setNeedsLayout()
        finder.layoutIfNeeded()

        func presses(_ slider: UISlider) -> Int {
            (slider.gestureRecognizers ?? []).filter { $0.delegate === coordinator }.count
        }
        #expect(presses(below) == 1, "the slider under the finder got no long press")
        #expect(presses(above) == 0, "a slider the finder does not cover got a long press")
    }
}
