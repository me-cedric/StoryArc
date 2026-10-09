internal import SwiftUI
internal import UIKit

/// A long press anywhere on the slider it sits behind, the thumb included.
///
/// `reading-themes`: a long press on a slider returns that axis to its preset. SwiftUI's own
/// `LongPressGesture` reaches only the track: a touch that lands on the thumb belongs to the
/// slider's control tracking, and a gesture on an ancestor view never begins for it (task
/// 25.6). A recogniser on the slider itself sits in the same touch, recognises beside the
/// tracking, and leaves a drag from the thumb alone, because it fails the moment the finger
/// moves.
struct SliderLongPress: UIViewRepresentable {
    /// How far a finger may stray and still count as a press rather than a drag.
    let travel: CGFloat
    let onLongPress: () -> Void

    /// Whether a finger that went down at `start` and lifted at `end` pressed rather than dragged.
    static func isPress(from start: CGPoint, to end: CGPoint, travel: CGFloat) -> Bool {
        abs(end.x - start.x) < travel && abs(end.y - start.y) < travel
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Finder {
        let finder = Finder()
        finder.coordinator = context.coordinator
        return finder
    }

    func updateUIView(_ finder: Finder, context: Context) {
        context.coordinator.action = onLongPress
        context.coordinator.travel = travel
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var action: () -> Void = {}
        var travel: CGFloat = 10
        private var start: CGPoint = .zero

        /// The reset waits for the lift and drops when the finger travelled, so a reader who
        /// rests on the thumb and then drags keeps the axis they were setting.
        @objc func pressed(_ recogniser: UILongPressGestureRecognizer) {
            handle(recogniser.state, at: recogniser.location(in: nil))
        }

        func handle(_ state: UIGestureRecognizer.State, at here: CGPoint) {
            switch state {
            case .began: start = here
            case .ended:
                if SliderLongPress.isPress(from: start, to: here, travel: travel) { action() }
            default: break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }

    /// Finds the slider next to it once both are on screen, and gives it the recogniser.
    final class Finder: UIView {
        weak var coordinator: Coordinator?
        private weak var attachedTo: UISlider?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if attachedTo == nil, window != nil { attach() }
        }

        private func attach() {
            guard let coordinator, let slider = nearestSlider(), slider !== attachedTo else { return }
            attachedTo = slider
            let press = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.pressed))
            press.cancelsTouchesInView = false
            press.delegate = coordinator
            slider.addGestureRecognizer(press)
        }

        /// The slider drawn under this view, by position, so a neighbour is never picked.
        private func nearestSlider() -> UISlider? {
            let centre = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: nil)
            var ancestor = superview
            while let level = ancestor {
                let under = level.sliders().first {
                    $0.convert($0.bounds, to: nil).contains(centre)
                }
                if let under { return under }
                ancestor = level.superview
            }
            return nil
        }
    }
}

private extension UIView {
    func sliders() -> [UISlider] {
        (self as? UISlider).map { [$0] } ?? subviews.flatMap { $0.sliders() }
    }
}
