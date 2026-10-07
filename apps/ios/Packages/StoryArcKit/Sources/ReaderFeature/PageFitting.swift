internal import CoreGraphics

internal import StoryArcCore

/// The record of which fit a page has actually been opened at.
///
/// `comic-reader` gives a page a starting scale and then leaves the zoom alone --
/// "a reader who pinches from fit-to-width stays zoomed until they pinch back or turn the
/// page". So the fit is applied once per page, mode and viewport, and this is the record that
/// stops it being applied a second time over the reader's own pinch.
///
/// The record used to be written the moment a fit was *asked for*, which is wrong on a cold
/// launch straight into the reader. SwiftUI proposes a size before UIKit has laid the scroll
/// view out, so the fit was computed against a view whose bounds were still zero, could not
/// take, and was marked applied anyway -- the page stayed at its own pixel size in the corner
/// until something else changed the key. A fit now counts as applied only once there is a
/// laid-out view to apply it to, and until then it stays owed.
///
/// It lives away from the scroll view because it needs one no more than the arithmetic below
/// does, and both are then tested on the host rather than on a simulator.
struct AppliedFit {
    /// The page, mode and viewport the current zoom was set from, or nothing yet.
    private var applied: String?

    /// What tells one fit from another.
    ///
    /// Whole points, because a viewport that differs by a hairline mid-rotation is the same
    /// fit and re-applying it would throw away a pinch the reader had just made.
    static func key(pageID: String, fit: PageFit, viewport: CGSize) -> String {
        "\(pageID)|\(fit.rawValue)|\(Int(viewport.width))x\(Int(viewport.height))"
    }

    /// Whether `key` still has to be applied to a view of `layout` size, recording it as
    /// applied when the answer is yes.
    ///
    /// A `layout` of zero is a view UIKit has not sized yet. Nothing can be fitted to one, so
    /// nothing is remembered either: the same fit is claimed again on the pass that gives the
    /// view a size, which is what makes a page that arrived before layout fit once it happens.
    mutating func claim(_ key: String, layout: CGSize) -> Bool {
        guard layout.width > 0, layout.height > 0 else { return false }
        guard applied != key else { return false }
        applied = key
        return true
    }
}

/// A fit a page is owed: everything needed to open it, held until there is a view to open it in.
///
/// A value rather than four arguments passed around a scroll view, because the fit may have to
/// wait: it is asked for on the way in and applied on whichever pass first has a laid-out view.
/// Keeping the arithmetic here as well means the whole of it is exercised on the host.
struct OwedFit {
    /// What ``AppliedFit`` compares to decide whether this fit still has to be applied.
    let key: String
    let mode: PageFit
    let imageSize: CGSize
    let viewport: CGSize
    /// What the reader pinched to on the last page, as a multiple of that page's own
    /// fit, carried into this one. See ``openingScale(fitScale:carried:mode:)``.
    let carried: CGFloat?
    /// Which side a page carried into horizontal slack opens against. See
    /// ``openingXOffset(contentWidth:boundsWidth:isRightToLeft:)``.
    let isRightToLeft: Bool

    init(
        pageID: String,
        mode: PageFit,
        imageSize: CGSize,
        viewport: CGSize,
        carried: CGFloat? = nil,
        isRightToLeft: Bool = false
    ) {
        self.key = AppliedFit.key(pageID: pageID, fit: mode, viewport: viewport)
        self.mode = mode
        self.imageSize = imageSize
        self.viewport = viewport
        self.carried = carried
        self.isRightToLeft = isRightToLeft
    }

    /// How far a page may be magnified: the scroll view's maximum zoom scale.
    static let zoomCeiling: CGFloat = 6

    /// The zoom scale the page opens at, never past what the view will hold.
    func scale(upTo ceiling: CGFloat) -> CGFloat {
        min(openingScale(fitScale: fitScale(upTo: .greatestFiniteMagnitude), carried: carried, mode: mode), ceiling)
    }

    /// The chosen fit's own scale, with nothing carried: what a double-tap goes back to
    /// (D5), and what a carried zoom is a multiple of (D6).
    func fitScale(upTo ceiling: CGFloat) -> CGFloat {
        let fit = mode.scale(
            fitted: fitted(imageSize, in: viewport),
            viewport: viewport,
            pixelWidth: imageSize.width
        )
        return min(fit, ceiling)
    }

    /// Whether the page opens at its top rather than its middle.
    ///
    /// `comic-reader` asks for exactly this when a turn keeps the zoom: fit-to-width and
    /// original size are read downwards, and starting halfway down one reads as a scroll
    /// position left over from somewhere else.
    var opensAtTheTop: Bool { mode == .width || mode == .original }
}

/// The page's size on screen at fit-to-screen, which every mode is a multiple of.
///
/// Expressing the four modes against this one size rather than as four layouts is what lets
/// pinch, double-tap and the fit control share a single number -- see `PageFit.scale`.
func fitted(_ imageSize: CGSize, in viewport: CGSize) -> CGSize {
    guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
    let scale = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
    return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
}

/// Whether a double-tap should zoom back to the fit scale, rather than in from it.
///
/// `comic-reader`: "double-tap toggles between fit and a zoomed level centred on the
/// tapped point". Decision D5: "fit" is the chosen fit mode's own scale, not a fixed
/// minimum — fit-to-width and fit-to-height are each greater than 1, and comparing
/// against a fixed 1 zoomed a page that was already at its chosen fit in further on
/// the first tap instead of the second. The tolerance absorbs the rounding a scroll
/// view's own zoom scale carries, which an exact comparison would read as "past fit"
/// forever.
func isZoomedPastFit(currentScale: CGFloat, fitScale: CGFloat) -> Bool {
    currentScale > fitScale * 1.01
}

/// Where a double-tap at the chosen fit zooms in to (D5): `factor` times that fit, about
/// the tapped point, and never past what the view will hold.
///
/// A multiple of the fit rather than a fixed scale: a fit-to-width page in landscape
/// can already sit above a fixed 2.5, and "zooming in" to 2.5 from there zoomed out.
func doubleTapZoomInScale(fitScale: CGFloat, factor: CGFloat, ceiling: CGFloat) -> CGFloat {
    min(fitScale * factor, ceiling)
}

/// The scale a page opens at: the chosen fit's own scale, or a carried pinch.
///
/// Decision D6: "zoom level" means the pinched scale, and in fit-to-width it "carries
/// to the next page" rather than resetting on every turn — every other mode still
/// resets, which is what "a reader who pinches ... stays zoomed until they ... turn
/// the page" already meant before this.
///
/// `carried` is the pinch as a multiple of the last page's own fit, not a raw scale: a
/// raw scale is relative to each page's fit-to-screen, which moves with the page's shape,
/// so a page opened at its plain fit carried that fit into a narrower page and opened it
/// magnified. A multiple at the fit, within ``isZoomedPastFit``'s tolerance, carries
/// nothing.
func openingScale(fitScale: CGFloat, carried: CGFloat?, mode: PageFit) -> CGFloat {
    guard mode == .width, let carried, isZoomedPastFit(currentScale: carried, fitScale: 1)
    else { return fitScale }
    return fitScale * carried
}

/// The horizontal offset a page opens at, when ``OwedFit/opensAtTheTop`` is true.
///
/// Decision D6: a carried zoom past fit-to-width can leave horizontal slack, and a
/// manga opens against the side its reading order starts from — the right — rather
/// than always the left.
func openingXOffset(contentWidth: CGFloat, boundsWidth: CGFloat, isRightToLeft: Bool) -> CGFloat {
    guard isRightToLeft else { return 0 }
    return max(0, contentWidth - boundsWidth)
}
