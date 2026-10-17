import CoreGraphics
import StoryArcCore

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

    /// The zoom for the page a turn lands on.
    ///
    /// `comic-reader`, *Zoom persists across pages*: the next page keeps the zoom level and
    /// opens at its top, on the side reading starts from — the left edge, or the right in a
    /// right-to-left publication. A fitted page stays fitted.
    func turned(isRightToLeft: Bool, fittedSize: CGSize, viewport: CGSize) -> ZoomModel {
        guard isZoomed else { return fitted() }
        var next = self
        let slackX = max(0, (fittedSize.width * scale - viewport.width) / 2)
        let slackY = max(0, (fittedSize.height * scale - viewport.height) / 2)
        next.offset = CGSize(width: isRightToLeft ? -slackX : slackX, height: slackY)
        return next
    }

    /// The page sized by a fit mode, opened at its top on the side reading starts from.
    ///
    /// `comic-reader`, *Fit modes*: fit to screen, width, height and original size, each a
    /// multiple of fit-to-screen (`PageFit.scale`), so pinch, the keys and a double click
    /// keep working on the one number. Never past the ceiling.
    func fitting(
        _ fit: PageFit, fittedSize: CGSize, viewport: CGSize, pixelWidth: CGFloat, isRightToLeft: Bool
    ) -> ZoomModel {
        let proposed = fit.scale(fitted: fittedSize, viewport: viewport, pixelWidth: pixelWidth)
        var next = ZoomModel()
        next.scale = min(max(proposed, 1), Self.ceiling)
        guard next.isZoomed else { return ZoomModel() }
        return next.turned(isRightToLeft: isRightToLeft, fittedSize: fittedSize, viewport: viewport)
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
