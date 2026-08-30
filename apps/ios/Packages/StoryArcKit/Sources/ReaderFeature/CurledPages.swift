internal import CoreGraphics
internal import SwiftUI

internal import StoryArcCore

/// A page being turned by the finger.
///
/// `page-transitions` asks for four things that are one gesture: the page follows the
/// finger in real time; past halfway the turn completes and before it the page springs
/// back; a flick completes regardless of distance; and a new drag during the settle
/// takes over from where the page is rather than snapping.
///
/// The shader is the twin of Android's AGSL, down to the constants — `design.md` calls
/// for one projection "expressed twice rather than solved twice".
///
/// Interruption is the awkward one here, because `withAnimation` moves the state it
/// animates to its destination at once and interpolates only what is drawn: `progress`
/// reads 1 the instant a settle begins, which is no use to a finger landing mid-settle.
/// ``Curling`` is how the drawn value is recovered, and ``CurlTurn`` is the arithmetic
/// that carries it into the new drag.
struct CurledPages: View {
    /// The page being turned away.
    let page: CGImage?
    /// The page underneath it, or `nil` at the last page.
    let beneath: CGImage?
    let isRightToLeft: Bool
    /// What shows behind and beside the page. See ``ReaderModel/matte``.
    let matte: Color
    /// Called once a turn has completed.
    let onTurned: () -> Void
    /// A press that was not a drag: the caller decides what it means.
    let onTap: (CGPoint, CGSize) -> Void

    /// Where the turn is *heading*: 0 for a flat page, 1 for one fully turned.
    ///
    /// Not where it is. A settle sets this to its destination at once, and only what is
    /// drawn moves gradually — see ``stand`` for where the page actually is.
    @State private var progress: Double = 0

    /// Where the page stands this frame, written as SwiftUI interpolates the settle.
    ///
    /// Deliberately not observed: it is written on every frame of an animation this view
    /// is already driving, and observing it would redraw the view to tell it what it just
    /// said. The gesture reads it once, when a drag takes the turn over.
    @State private var stand = CurlStand()

    /// Where the page stood when the current drag took it over, and the translation that
    /// drag had already accumulated by then. Together they make the drag an offset from
    /// the page rather than an absolute reading of the finger.
    @State private var base: Double = 0
    @State private var origin: Double = 0
    @State private var isDragging = false

    /// What the drag had reached when it ended, kept so the release decision does not
    /// depend on where an in-flight animation happens to be.
    @State private var reached: Double = 0

    /// Which settle is in flight. Bumped when a drag takes the turn over, so the settle
    /// it interrupted can tell that finishing is no longer its business.
    @State private var settle = 0

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                // The matte behind, because the shader leaves the letterbox transparent
                // rather than smearing the page's edge pixel across it.
                matte

                if let page {
                    Curling(progress: progress, stand: stand) { drawn in
                        Rectangle()
                            .fill(shader(for: page, in: size, at: drawn))
                    }
                }
            }
            .contentShape(.rect)
            .gesture(turnGesture(in: size))
            .onTapGesture { location in onTap(location, size) }
        }
    }

    // MARK: - The shader

    private func shader(for page: CGImage, in size: CGSize, at progress: Double) -> Shader {
        ShaderLibrary.bundle(.module).pageCurl(
            .float(progress),
            .float(Self.crease),
            .float(Self.shadow),
            .float(isRightToLeft ? -1 : 1),
            .float(Self.back),
            .float2(size.width, size.height),
            .image(Image(decorative: page, scale: 1)),
            // The outgoing page stands in for a missing one, so the last page still
            // turns rather than tearing to nothing. Whether it *may* turn is the
            // caller's business, not the shader's.
            .image(Image(decorative: beneath ?? page, scale: 1))
        )
    }

    // MARK: - The gesture

    private func turnGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    // The turn is taken over here. Whatever settle is running is no
                    // longer its own to finish, the page's *drawn* progress becomes the
                    // base this drag is measured from, and the eight points that only
                    // proved the finger meant a drag are not also spent turning the page.
                    settle &+= 1
                    base = stand.value
                    origin = value.translation.width
                }
                reached = CurlTurn.progress(
                    base: base,
                    travel: value.translation.width - origin,
                    width: size.width,
                    isRightToLeft: isRightToLeft
                )
                // No animation on the drag itself: the page follows the finger, and an
                // animation between finger positions is a page lagging behind it.
                progress = reached
            }
            .onEnded { value in
                isDragging = false
                let velocity = isRightToLeft
                    ? value.predictedEndTranslation.width - value.translation.width
                    : value.translation.width - value.predictedEndTranslation.width
                let settles = CurlTurn.settles(
                    progress: reached,
                    isFlick: velocity > Self.flickPoints
                )
                let ticket = settle

                withAnimation(.spring(duration: 0.3)) {
                    progress = settles ? 1 : 0
                } completion: {
                    // A settle a later drag took over is that drag's to finish, not this
                    // one's: SwiftUI runs this completion when the animation is *removed*,
                    // which an interruption does, and turning the page here would turn it
                    // under a finger still on the screen.
                    guard settles, settle == ticket else { return }
                    // The page swap first, then the reset: the other order shows the
                    // outgoing page flat for a frame before it goes.
                    onTurned()
                    progress = 0
                    stand.value = 0
                }
            }
    }

    // MARK: - Constants, shared with the Android shader

    private static let crease = 0.06
    private static let shadow = 0.05
    private static let back = 0.55

    /// How far a finger has to be predicted to travel for the turn to complete anyway.
    ///
    /// `predictedEndTranslation` is SwiftUI's own flick model, so this is a threshold on
    /// its answer rather than a velocity calculation of ours.
    private static let flickPoints: Double = 40
}

/// The curl, drawn at the value SwiftUI is actually interpolating.
///
/// A view that conforms to `Animatable` is handed every step of the animation through
/// `animatableData`, which is the only way to know where a settle currently stands — the
/// state that started it jumped to its destination the moment it was set. So the shader
/// is built from the interpolated value, and the same value is left in ``CurlStand`` for
/// the gesture to pick the page up from.
private struct Curling<Content: View>: View, @MainActor Animatable {
    var progress: Double
    let stand: CurlStand
    @ViewBuilder let content: (Double) -> Content

    var animatableData: Double {
        get { progress }
        set {
            progress = newValue
            stand.value = newValue
        }
    }

    var body: some View { content(progress) }
}

/// Where the curl stands this frame.
///
/// A reference type because the interpolation and the gesture hold two different copies
/// of the same view struct, and a value written into one would not be seen by the other.
/// Written from ``Curling``'s main-actor-isolated `Animatable` conformance and read from
/// the gesture, which is the same actor: no synchronisation to get wrong.
@MainActor
private final class CurlStand {
    var value: Double = 0
}

/// Where a page stands mid-turn, and what a finger does to it from there.
///
/// Pulled out of the gesture so it can be tested without a touch screen, the way
/// `SpreadLayout` and `PrefetchWindow` are: this is the whole rule, and the rest of
/// ``CurledPages`` is SwiftUI's gesture plumbing. Android's `CurlTurn` is its twin.
enum CurlTurn {

    /// Travel in turn-space: positive is towards a completed turn.
    ///
    /// A right-to-left publication turns forward when the finger moves the other way, so
    /// one sign carries the whole mirroring.
    static func forward(travel: Double, isRightToLeft: Bool) -> Double {
        isRightToLeft ? travel : -travel
    }

    /// Where the page stands after `travel` points of drag from `base`.
    ///
    /// The base is the whole point. `comic-reader` requires a drag begun during a settle
    /// to take over "from the current position without the page snapping", so the drag is
    /// an *offset* from where the page stands rather than an absolute reading of the
    /// finger: a settle caught at 0.8 and nudged one point stays at 0.8, where reading the
    /// finger alone would have put it at 0.001.
    ///
    /// It is also what lets a caught settle be pushed back. Clamping an absolute reading
    /// at zero made every backwards move mean "no progress"; clamping base plus travel
    /// makes it mean "less progress", which is the same gesture read correctly.
    ///
    /// - Parameters:
    ///   - base: the page's progress when the finger took it over, 0 for a flat page.
    ///   - travel: raw horizontal points since the drag was recognised.
    ///   - width: what a whole turn is measured against. A width nothing has measured yet
    ///     leaves the page where it stands rather than dividing by it.
    static func progress(
        base: Double,
        travel: Double,
        width: Double,
        isRightToLeft: Bool
    ) -> Double {
        guard width > 0 else { return min(max(base, 0), 1) }
        let offset = forward(travel: travel, isRightToLeft: isRightToLeft) / width
        return min(max(base + offset, 0), 1)
    }

    /// Whether a released turn completes rather than springing back.
    ///
    /// Past halfway it completes; before it, it springs back. A flick completes whatever
    /// the distance, because a fast finger has already said what it meant — and a page
    /// that never left flat is not a turn at all, however fast the finger left it.
    static func settles(progress: Double, isFlick: Bool) -> Bool {
        progress > 0.5 || (isFlick && progress > 0.05)
    }
}
