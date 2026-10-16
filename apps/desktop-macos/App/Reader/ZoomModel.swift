import CoreGraphics

/// The zoom of one page in a Mac reader window, as a multiple of its fit.
///
/// `desktop-experience`, *Zoom and pan with a pointer*. Every input — pinch, Command and
/// the wheel, a double click, the keys — lands on the one number, which is what lets the
/// menu's Fit Page and a double click agree. The limits are the iOS zoom model's: a ceiling
/// of 6 (`OwedFit.zoomCeiling`) and a double-tap level of 2.5 times the fit
/// (`ZoomablePage.Coordinator.zoomedScale`). Both are internal to `ReaderFeature`, so they
/// are copied here until parent task 5.12 shares them. Task 2.13.
struct ZoomModel: Equatable, Sendable {
    static let ceiling: CGFloat = 6
    static let doubleClickFactor: CGFloat = 2.5
    /// One menu or key step. Eight steps from fit reach the ceiling.
    static let keyStep: CGFloat = 1.25
    /// How much one wheel notch zooms with Command held.
    static let wheelStep: CGFloat = 1.1
    /// Past-fit tolerance, so a scroll view's rounding never reads as "zoomed".
    static let fitTolerance: CGFloat = 1.01

    /// Multiple of the fit. 1 is the page fitted to the viewport.
    private(set) var scale: CGFloat = 1
    /// How far the zoomed page is panned from centred, in points.
    private(set) var offset: CGSize = .zero

    var isZoomed: Bool { scale > Self.fitTolerance }

    func fitted() -> ZoomModel { ZoomModel() }

    func zoomedIn() -> ZoomModel { scaled(to: scale * Self.keyStep) }

    func zoomedOut() -> ZoomModel { scaled(to: scale / Self.keyStep) }

    /// A pinch, as a multiplier over the scale at its start.
    func magnified(by factor: CGFloat) -> ZoomModel { scaled(to: scale * factor) }

    /// A wheel notch with the system modifier held. Positive is towards the reader.
    func wheeled(by notches: CGFloat) -> ZoomModel {
        scaled(to: scale * pow(Self.wheelStep, notches))
    }

    /// *Double click*: the phone's double-tap level from fit, and fit again from anywhere else.
    func doubleClicked() -> ZoomModel {
        isZoomed ? fitted() : scaled(to: Self.doubleClickFactor)
    }

    /// A pan by `delta`, kept inside the page's edges for this viewport.
    func panned(by delta: CGSize, fittedSize: CGSize, viewport: CGSize) -> ZoomModel {
        var next = self
        next.offset = Self.clamped(
            CGSize(width: offset.width + delta.width, height: offset.height + delta.height),
            fittedSize: fittedSize, scale: scale, viewport: viewport
        )
        return next
    }

    /// The offset with the page's edges respected after a resize or a zoom change.
    func settled(fittedSize: CGSize, viewport: CGSize) -> ZoomModel {
        var next = self
        next.offset = Self.clamped(offset, fittedSize: fittedSize, scale: scale, viewport: viewport)
        return next
    }

    /// Clamps to the limits; a step beyond one changes nothing and says nothing.
    private func scaled(to proposed: CGFloat) -> ZoomModel {
        var next = self
        next.scale = min(max(proposed, 1), Self.ceiling)
        if !next.isZoomed { next.offset = .zero }
        return next
    }

    /// The furthest a zoomed page may be panned: half the overflow on each axis, and
    /// nothing at all on an axis where the page still fits.
    static func clamped(_ offset: CGSize, fittedSize: CGSize, scale: CGFloat, viewport: CGSize) -> CGSize {
        let slackX = max(0, (fittedSize.width * scale - viewport.width) / 2)
        let slackY = max(0, (fittedSize.height * scale - viewport.height) / 2)
        return CGSize(
            width: min(max(offset.width, -slackX), slackX),
            height: min(max(offset.height, -slackY), slackY)
        )
    }
}
