internal import SwiftUI

/// What a refused discrete turn shows besides its haptic (task 8.11, D13).
///
/// `page-transitions` "Turning at a boundary": "the page resists with a bounded rubber-band
/// and returns". A drag in Slide or Scroll already gets the container's own overscroll. A
/// tap or a key had only the haptic. Under Reduce Motion the give becomes a brief dim.
/// Android's `RefusalResponse` is the same rule.
enum RefusalResponse: Equatable {
    case nudge(CGFloat)
    case dim

    /// How far the page gives, in points, before it springs back.
    static let reach: CGFloat = 24

    /// The response for one refused turn, or `nil` in a scroll, which has no page to give.
    ///
    /// A turn is refused only going back from the first page. So the page gives the way the
    /// missing page would have pushed it: right in left-to-right, left in right-to-left.
    static func of(reduceMotion: Bool, isRightToLeft: Bool, scrolls: Bool) -> RefusalResponse? {
        if scrolls { return nil }
        return reduceMotion ? .dim : .nudge(isRightToLeft ? -reach : reach)
    }
}

/// Plays a ``RefusalResponse`` each time `trigger` changes.
struct RefusalResistance: ViewModifier {
    let trigger: Int
    let response: RefusalResponse?

    @State private var offset: CGFloat = 0
    @State private var isDimmed = false

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .opacity(isDimmed ? 0.6 : 1)
            .onChange(of: trigger) {
                switch response {
                case .nudge(let reach):
                    withAnimation(.easeOut(duration: 0.1)) { offset = reach } completion: {
                        withAnimation(.spring(duration: 0.35, bounce: 0.4)) { offset = 0 }
                    }
                case .dim:
                    withAnimation(.easeInOut(duration: 0.1)) { isDimmed = true } completion: {
                        withAnimation(.easeInOut(duration: 0.15)) { isDimmed = false }
                    }
                case nil:
                    break
                }
            }
    }
}
