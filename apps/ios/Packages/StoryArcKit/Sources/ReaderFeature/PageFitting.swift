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

    init(pageID: String, mode: PageFit, imageSize: CGSize, viewport: CGSize) {
        self.key = AppliedFit.key(pageID: pageID, fit: mode, viewport: viewport)
        self.mode = mode
        self.imageSize = imageSize
        self.viewport = viewport
    }

    /// The zoom scale the page opens at, never past what the view will hold.
    func scale(upTo ceiling: CGFloat) -> CGFloat {
        min(
            mode.scale(
                fitted: fitted(imageSize, in: viewport),
                viewport: viewport,
                pixelWidth: imageSize.width
            ),
            ceiling
        )
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
