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
    /// The page behind this one, or `nil` at the first page.
    ///
    /// `page-transitions`: the turn has a direction, and a backwards drag turns this sheet
    /// over the page in view. `nil` is what stops the first page turning backwards.
    let previous: CGImage?
    let isRightToLeft: Bool
    /// What shows behind and beside the page. See ``ReaderModel/matte``.
    let matte: Color
    /// The series' brightness, contrast, inversion and greyscale.
    ///
    /// `comic-reader` "Persisting adjustments": applied to the turning sheet only, not to
    /// ``matte`` — the matte is what shows *around* the page, and inverting a black matte
    /// to white along with the page would be a second bug in the middle of fixing this one.
    /// The border trim and the sharpening are baked into `page`, `beneath` and `previous`
    /// themselves before this view ever sees them, the same way every other container
    /// applies them.
    var adjustments = ImageAdjustments()
    /// Whether the current page turned out to be undecodable, rather than merely not
    /// decoded yet. See ``PageProblem``.
    var isUnavailable = false
    /// What the current page turned out to be, when it could not be decoded.
    var codecName: String?
    /// Called once a forward turn has completed.
    let onTurned: () -> Void
    /// Called once a backwards turn has completed.
    let onTurnedBack: () -> Void
    /// A press that was not a drag: the caller decides what it means.
    let onTap: (CGPoint, CGSize) -> Void
    /// A turn asked for by a tap, a key or a controller rather than by a finger on the
    /// page. Cleared here once the curl has run it. See ``CurlRequest``.
    @Binding var request: CurlRequest?

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

                Curling(progress: progress, stand: stand) { drawn in
                    let sheets = CurlTurn.sheets(
                        progress: drawn, page: page, beneath: beneath, previous: previous
                    )
                    if let turning = sheets.turning {
                        Rectangle()
                            .fill(
                                shader(
                                    for: turning,
                                    under: sheets.under,
                                    in: size,
                                    at: sheets.progress
                                )
                            )
                            .adjusted(adjustments)
                    } else if isUnavailable {
                        // `publication-formats`: a page that could not be decoded is named
                        // rather than left as a bare matte, in Curl as in every other mode.
                        PageProblem(codecName: codecName)
                    } else {
                        // `comic-reader`: "a progress indicator appears only after 400 ms".
                        // Only reachable at rest — a drag never starts on a page that has
                        // not decoded, because `sheets.turning` is flat `page` there.
                        DelayedProgressView()
                    }
                }
            }
            .contentShape(.rect)
            .gesture(turnGesture(in: size))
            .onTapGesture { location in onTap(location, size) }
            .onChange(of: request) { _, asked in
                if let asked { run(asked) }
            }
            // A turn the reader left mid-drag never reaches its settle, so the count is
            // closed here instead. Android's `onDispose` is the twin.
            .onDisappear { FrameProbe.cancel() }
        }
    }

    // MARK: - The shader

    private func shader(
        for page: CGImage,
        under: CGImage?,
        in size: CGSize,
        at progress: Double
    ) -> Shader {
        ShaderLibrary.bundle(.module).pageCurl(
            .float(progress),
            .float(Float(PageRoll.crease)),
            .float(Float(PageRoll.shadow)),
            .float(isRightToLeft ? -1 : 1),
            .float(Float(PageRoll.back)),
            .float(Float(PageRoll.radiusMax)),
            .float(Float(PageRoll.lean)),
            .float(Float(PageRoll.rim)),
            .float2(size.width, size.height),
            .image(Image(decorative: page, scale: 1)),
            // The outgoing page stands in for a missing one, so the last page still
            // turns rather than tearing to nothing. Whether it *may* turn is the
            // caller's business, not the shader's.
            .image(Image(decorative: under ?? page, scale: 1))
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
                    // The turn starts here and ends when its settle completes, so a count
                    // covers the drag and the spring and nothing else. Off unless armed.
                    FrameProbe.began()
                }
                reached = CurlTurn.progress(
                    base: base,
                    travel: value.translation.width - origin,
                    width: size.width,
                    isRightToLeft: isRightToLeft,
                    canTurnBack: previous != nil,
                    canTurnForward: beneath != nil
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
                    isFlick: CurlTurn.flicks(velocity: velocity, progress: reached)
                )
                let backwards = reached < 0
                let ticket = settle

                withAnimation(.spring(duration: 0.3)) {
                    progress = settles ? (backwards ? -1 : 1) : 0
                } completion: {
                    // A settle a later drag took over is that drag's to finish, not this
                    // one's: SwiftUI runs this completion when the animation is *removed*,
                    // which an interruption does, and turning the page here would turn it
                    // under a finger still on the screen.
                    guard settle == ticket else { return }
                    // The turn is over either way — a page that sprang back still spent
                    // frames. A settle a drag took over is that drag's to close, which is
                    // why this sits behind the ticket check and not in front of it.
                    FrameProbe.ended()
                    guard settles else { return }
                    // The page swap first, then the reset: the other order shows the
                    // outgoing page flat for a frame before it goes.
                    if backwards { onTurnedBack() } else { onTurned() }
                    progress = 0
                    stand.value = 0
                }
            }
    }

    // MARK: - A turn nobody dragged

    /// Runs a ``CurlRequest`` as the spring a released drag would have run.
    ///
    /// The same settle, the same ticket and the same ordering as `turnGesture`'s release:
    /// the page swap first, then the reset, so the outgoing page is never drawn flat for
    /// a frame on its way out. A finger already on the page outranks the request — it is
    /// the one thing that can be mid-turn when this arrives — and the request is left in
    /// place rather than cleared, because the next one carries a later serial anyway.
    private func run(_ asked: CurlRequest) {
        guard !isDragging else { return }
        settle &+= 1
        let ticket = settle
        withAnimation(.spring(duration: 0.3)) {
            progress = asked.isForward ? 1 : -1
        } completion: {
            guard settle == ticket else { return }
            if asked.isForward { onTurned() } else { onTurnedBack() }
            progress = 0
            stand.value = 0
            request = nil
        }
    }

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
