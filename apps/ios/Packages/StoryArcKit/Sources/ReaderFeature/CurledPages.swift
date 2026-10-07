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
/// **At rest this is the reader's normal page body** (D33, task 8.16): the fit, the pinch
/// and the PDF marks, exactly as Fast fade draws them. The shader stands over the body only
/// while a turn runs, starting from where the body drew the page and ending where the next
/// page opens. The finger belongs to the body's own pan recogniser, which hands each phase
/// here through ``CurlDrag``, so a zoomed page pans and only a page with no sideways slack
/// turns.
///
/// The shader is the twin of Android's AGSL, down to the constants — `design.md` calls
/// for one projection "expressed twice rather than solved twice".
///
/// Interruption is the awkward one here, because `withAnimation` moves the state it
/// animates to its destination at once and interpolates only what is drawn: `progress`
/// reads 1 the instant a settle begins, which is no use to a finger landing mid-settle.
/// ``Curling`` is how the drawn value is recovered, and ``CurlTurn`` is the arithmetic
/// that carries it into the new drag.
struct CurledPages<Content: View, Underneath: View>: View {
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
    /// Whether the publication ends after this page, so a forward turn lifts it off the end
    /// screen (D10, task 8.5). See ``CurlTurn/under(beneath:endsHere:)``.
    var endsHere = false
    /// Whether the page in view is a spread. Its two halves are two scroll views, so neither
    /// one's frame is the sheet's, and the sheet is fitted to the whole area instead.
    var isSpread = false
    /// Where `beneath` and `previous` will open, given the sheet and this view's size. See
    /// ``CurlSheetFrame/opening(imageSize:viewport:fit:carried:isRightToLeft:)``.
    var beneathOpens: (CGImage, CGSize) -> CGRect = { _, size in CGRect(origin: .zero, size: size) }
    var previousOpens: (CGImage, CGSize) -> CGRect = { _, size in CGRect(origin: .zero, size: size) }
    /// The reader's page body, drawn at rest and kept under the sheet while a turn runs.
    let content: Content
    /// The end-of-publication screen, drawn under the sheet while the last page lifts.
    let underneath: Underneath
    /// Called once a forward turn has completed.
    let onTurned: () -> Void
    /// Called once a backwards turn has completed.
    let onTurnedBack: () -> Void
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

    /// Whether the shader stands over the body: from the moment a turn starts until its
    /// settle lands.
    @State private var isTurning = false

    /// Where the body drew the page when this turn started, in this view's space, or `nil`
    /// to fit it to the whole area.
    @State private var sheetFrame: CGRect?

    /// The one drag handle the page body reports to. See ``CurlDrag``.
    @State private var drag = CurlDrag()

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let screen = geometry.frame(in: .global)
            ZStack {
                content
                    .environment(\.curlDrag, wired(in: size, at: screen))
                if isTurning {
                    Curling(progress: progress, stand: stand) { drawn in
                        turning(at: drawn, in: size)
                    }
                    // The finger stays with the body's pan recogniser, which is what lets
                    // a drag take over a settle still running.
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: request) { _, asked in
                if let asked { run(asked, at: screen) }
            }
            // A turn the reader left mid-drag never reaches its settle, so the count is
            // closed here instead. Android's `onDispose` is the twin.
            .onDisappear { FrameProbe.cancel() }
        }
    }

    /// What lies under a forward turn of this page.
    private var under: CurlTurn.Under { CurlTurn.under(beneath: beneath, endsHere: endsHere) }

    // MARK: - The turning layer

    @ViewBuilder
    private func turning(at drawn: Double, in size: CGSize) -> some View {
        let sheets = CurlTurn.sheets(progress: drawn, page: page, beneath: beneath, previous: previous)
        let reveals = drawn > 0 && under == .endScreen
        ZStack {
            if reveals {
                // D10: the end screen is the next sheet. The matte stops at the sheet's
                // own rim so it shows through past the fold, and nothing on it answers a
                // touch until the turn has landed and the real one is up.
                underneath.accessibilityHidden(true)
                // The matte behind, because the shader leaves the letterbox transparent
                // rather than smearing the page's edge pixel across it.
                matte.clipShape(CurlSheetShape(progress: drawn, isRightToLeft: isRightToLeft))
            } else {
                matte
            }
            if let turning = sheets.turning {
                Rectangle()
                    .fill(shader(for: turning, sheets: sheets, at: drawn, reveals: reveals, in: size))
                    .adjusted(adjustments)
            } else if isUnavailable {
                // `publication-formats`: a page that could not be decoded is named
                // rather than left as a bare matte, in Curl as in every other mode.
                PageProblem(codecName: codecName)
            } else {
                // `comic-reader`: "a progress indicator appears only after 400 ms".
                DelayedProgressView()
            }
        }
    }

    // MARK: - The shader

    private func shader(
        for turning: CGImage,
        sheets: CurlTurn.Sheets<CGImage>,
        at drawn: Double,
        reveals: Bool,
        in size: CGSize
    ) -> Shader {
        let whole = CGRect(origin: .zero, size: size)
        // The same choice of sheets, made over where each one lies flat: the page where
        // the body drew it, and its neighbours where they will open.
        let frames = CurlTurn.sheets(
            progress: drawn,
            page: sheetFrame ?? whole,
            beneath: beneath.map { beneathOpens($0, size) } ?? whole,
            previous: previous.map { previousOpens($0, size) } ?? whole
        )
        // The outgoing page stands in for a missing one, so a sheet still decoding does
        // not tear to nothing. Past the last page the clear sheet lets the end screen show.
        let under = reveals ? CurlSheetFrame.clear ?? turning : sheets.under ?? turning
        return ShaderLibrary.bundle(.module).pageCurl(
            .float(sheets.progress),
            .float(Float(PageRoll.crease)),
            .float(Float(PageRoll.shadow)),
            .float(isRightToLeft ? -1 : 1),
            .float(Float(PageRoll.back)),
            .float(Float(PageRoll.radiusMax)),
            .float(Float(PageRoll.lean)),
            .float(Float(PageRoll.rim)),
            .float2(size.width, size.height),
            Self.frame(frames.turning ?? whole),
            Self.frame(frames.under ?? whole),
            .image(Image(decorative: turning, scale: 1)),
            .image(Image(decorative: under, scale: 1))
        )
    }

    private static func frame(_ rect: CGRect) -> Shader.Argument {
        .float4(rect.minX, rect.minY, rect.width, rect.height)
    }

    // MARK: - The drag

    /// The drag handle, answering for this pass. Replaced on every pass, so the drag never
    /// answers with a page the reader has already turned.
    private func wired(in size: CGSize, at screen: CGRect) -> CurlDrag {
        drag.handle = { follow($0, in: size, at: screen) }
        return drag
    }

    /// One phase of the finger, as the page body's pan recogniser reported it.
    private func follow(_ phase: CurlDrag.Phase, in size: CGSize, at screen: CGRect) {
        switch phase {
        case .began(let travel):
            isDragging = true
            // The turn is taken over here. Whatever settle is running is no longer its
            // own to finish, the page's *drawn* progress becomes the base this drag is
            // measured from, and the points that only proved the finger meant a drag are
            // not also spent turning the page.
            settle &+= 1
            base = stand.value
            origin = travel
            start(at: screen)
            // The turn starts here and ends when its settle completes, so a count covers
            // the drag and the spring and nothing else. Off unless armed.
            FrameProbe.began()
        case .changed(let travel):
            guard isDragging else { return }
            reached = CurlTurn.progress(
                base: base,
                travel: travel - origin,
                width: size.width,
                isRightToLeft: isRightToLeft,
                canTurnBack: previous != nil,
                canTurnForward: under != .nothing
            )
            // No animation on the drag itself: the page follows the finger, and an
            // animation between finger positions is a page lagging behind it.
            progress = reached
        case .ended(_, let velocity):
            guard isDragging else { return }
            isDragging = false
            release(velocity: velocity)
        }
    }

    /// The finger lifted: complete the turn or spring the page back.
    private func release(velocity: Double) {
        let flick = CurlTurn.forward(
            travel: CurlTurn.predictedTravel(velocity: velocity), isRightToLeft: isRightToLeft
        )
        let settles = CurlTurn.settles(
            progress: reached,
            isFlick: CurlTurn.flicks(velocity: flick, progress: reached)
        )
        let backwards = reached < 0
        settle(to: settles ? (backwards ? -1 : 1) : 0) {
            // The turn is over either way — a page that sprang back still spent frames.
            // A settle a drag took over is that drag's to close, which is why this sits
            // behind the ticket check in `settle(to:then:)`.
            FrameProbe.ended()
            guard settles else { return }
            if backwards { onTurnedBack() } else { onTurned() }
        }
    }

    /// Stands the shader over the body, from where the body drew the page.
    ///
    /// Only when no turn is already running: a drag that takes over a settle keeps the
    /// frame that turn started from.
    private func start(at screen: CGRect) {
        guard !isTurning else { return }
        sheetFrame = isSpread ? nil : drag.sheet().map { $0.offsetBy(dx: -screen.minX, dy: -screen.minY) }
        isTurning = true
    }

    /// Springs the page to `target`, then runs `landed` and puts the body back.
    ///
    /// SwiftUI runs the completion when the animation is *removed*, which an interruption
    /// does, and turning the page there would turn it under a finger still on the screen.
    /// So a settle a later drag took over is that drag's to finish, not this one's.
    private func settle(to target: Double, then landed: @escaping () -> Void) {
        let ticket = settle
        withAnimation(.spring(duration: 0.3)) {
            progress = target
        } completion: {
            guard settle == ticket else { return }
            // The page swap first, then the reset: the other order shows the outgoing
            // page flat for a frame before it goes.
            landed()
            progress = 0
            stand.value = 0
            isTurning = false
        }
    }

    // MARK: - A turn nobody dragged

    /// Runs a ``CurlRequest`` as the spring a released drag would have run.
    ///
    /// The same settle, the same ticket and the same ordering as a released drag: the page
    /// swap first, then the reset, so the outgoing page is never drawn flat for a frame on
    /// its way out. A finger already on the page outranks the request — it is the one thing
    /// that can be mid-turn when this arrives — and the request is left in place rather than
    /// cleared, because the next one carries a later serial anyway.
    private func run(_ asked: CurlRequest, at screen: CGRect) {
        guard !isDragging else { return }
        settle &+= 1
        start(at: screen)
        settle(to: asked.isForward ? 1 : -1) {
            if asked.isForward { onTurned() } else { onTurnedBack() }
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
