internal import CoreGraphics
internal import SwiftUI

#if os(iOS)
internal import UIKit
#endif

internal import DesignSystem
internal import StoryArcCore

// What is painted over a PDF page, and the arithmetic that puts it in the right place.
//
// The reader draws a page as a raster at whatever size the screen asked for, and everything
// the text layer reports is normalised to the page instead — `0...1` across and down. This is
// the one place the two meet.
//
// Android's `PdfPageOverlay` maps the same two spaces.

/// The marks and the live selection on one page, as one value.
///
/// One value rather than two properties on the page view, because they change together and a
/// view that took them separately would redraw twice for one gesture.
struct PdfPageDecoration: Equatable {
    var marks: [PdfPageMark] = []
    /// Normalised to the page, like the marks. Empty when nothing is selected.
    var selection: [CGRect] = []

    var isEmpty: Bool { marks.isEmpty && selection.isEmpty }

    static let none = PdfPageDecoration()
}

/// Where the page's artwork actually sits inside a view that is fitting it.
///
/// The page is drawn aspect-fit, so a portrait page in a landscape view has bars either side
/// and a point in the *view* is not a point on the *page*. Everything below converts through
/// this rectangle.
///
/// A free function over the existing `fitted(_:in:)` so the whole conversion is exercised on
/// the host, without a scroll view or a simulator.
func pageRect(of imageSize: CGSize, in viewSize: CGSize) -> CGRect {
    let size = fitted(imageSize, in: viewSize)
    guard size.width > 0, size.height > 0 else { return .zero }
    return CGRect(
        x: (viewSize.width - size.width) / 2,
        y: (viewSize.height - size.height) / 2,
        width: size.width,
        height: size.height
    )
}

/// A point in a fitting view, as a fraction of the page under it.
///
/// Clamped, because a drag that leaves the artwork still means "the edge of the page" rather
/// than a coordinate off it — a reader sweeping past the last word has selected to the end of
/// the line, not to nowhere.
func normalisedPoint(_ point: CGPoint, imageSize: CGSize, in viewSize: CGSize) -> CGPoint {
    let rect = pageRect(of: imageSize, in: viewSize)
    guard rect.width > 0, rect.height > 0 else { return .zero }
    return CGPoint(
        x: min(max((point.x - rect.minX) / rect.width, 0), 1),
        y: min(max((point.y - rect.minY) / rect.height, 0), 1)
    )
}

/// A normalised rectangle, back in the coordinates of a fitting view.
func viewRect(_ normalised: CGRect, imageSize: CGSize, in viewSize: CGSize) -> CGRect {
    let rect = pageRect(of: imageSize, in: viewSize)
    return CGRect(
        x: rect.minX + normalised.minX * rect.width,
        y: rect.minY + normalised.minY * rect.height,
        width: normalised.width * rect.width,
        height: normalised.height * rect.height
    )
}

#if os(iOS)
/// The marks and the selection, drawn over the page and under nothing.
///
/// A `UIView` inside the scroll view's content rather than a SwiftUI overlay on top of it: a
/// highlight belongs to the words, so it has to zoom and pan with them. An overlay outside the
/// scroll view would sit still while the page moved underneath it.
final class PdfPageOverlayView: UIView {
    /// The page's own pixel size, which is what the fit is computed from.
    var imageSize: CGSize = .zero { didSet { setNeedsDisplay() } }
    var decoration: PdfPageDecoration = .none { didSet { setNeedsDisplay() } }

    /// How much of the ink shows. Enough to read as a mark, little enough to read the words
    /// under it — the same compromise the EPUB navigator makes when it composites one.
    private let markOpacity: CGFloat = 0.38

    /// The live selection is drawn in the platform's own selection colour rather than in a
    /// highlight colour: it is not a mark yet, and colouring it yellow would say it was.
    private let selectionOpacity: CGFloat = 0.32

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isOpaque = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), imageSize.width > 0 else { return }

        for mark in decoration.marks {
            context.setFillColor(
                UIColor(mark.colour.swatch).withAlphaComponent(markOpacity).cgColor
            )
            context.fill(viewRect(mark.rect, imageSize: imageSize, in: bounds.size))
        }

        context.setFillColor(
            UIColor.tintColor.withAlphaComponent(selectionOpacity).cgColor
        )
        for rect in decoration.selection {
            context.fill(viewRect(rect, imageSize: imageSize, in: bounds.size))
        }
    }
}
#endif
