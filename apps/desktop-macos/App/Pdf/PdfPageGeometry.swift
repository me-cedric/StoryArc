import CoreGraphics

/// Where a page's artwork sits inside a view that fits it, and the two conversions between
/// the view and the page.
///
/// The text layer reports everything in page space, `0...1` across and down from the top
/// left, and the page is drawn aspect-fit, so a point in the view is not a point on the page.
/// A Mac copy of `ReaderFeature`'s `pageRect`, `normalisedPoint` and `viewRect`, which are
/// internal to the package. Task 4.6.
enum PdfPageGeometry {
    /// The rectangle the page fills when fitted and centred in `viewSize`.
    static func pageRect(of imageSize: CGSize, in viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (viewSize.width - size.width) / 2, y: (viewSize.height - size.height) / 2,
            width: size.width, height: size.height
        )
    }

    /// A point in the view as a fraction of the page under it, clamped: a drag past the edge
    /// means the edge of the page, not nowhere.
    static func normalisedPoint(_ point: CGPoint, imageSize: CGSize, in viewSize: CGSize) -> CGPoint {
        let rect = pageRect(of: imageSize, in: viewSize)
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(
            x: min(max((point.x - rect.minX) / rect.width, 0), 1),
            y: min(max((point.y - rect.minY) / rect.height, 0), 1)
        )
    }

    /// A page-space rectangle back in the view's coordinates.
    static func viewRect(_ normalised: CGRect, imageSize: CGSize, in viewSize: CGSize) -> CGRect {
        let rect = pageRect(of: imageSize, in: viewSize)
        return CGRect(
            x: rect.minX + normalised.minX * rect.width, y: rect.minY + normalised.minY * rect.height,
            width: normalised.width * rect.width, height: normalised.height * rect.height
        )
    }
}
