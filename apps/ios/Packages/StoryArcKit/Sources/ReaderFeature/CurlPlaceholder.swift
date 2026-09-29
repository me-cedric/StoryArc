internal import CoreGraphics
internal import SwiftUI

/// The sheet a curl turns to while that page has not decoded.
///
/// `page-transitions` "The next page is not ready": the turn "runs against a placeholder
/// holding the correct aspect ratio". Without one, the curl showed the outgoing page again
/// as the page beneath, and a backwards drag did nothing at all. Android's
/// `CurlPlaceholder` is the same shape.
enum CurlPlaceholder {
    /// The sheet at `display`: the decoded page, the placeholder while it decodes, or `nil`
    /// past either end of the publication. `nil` there is what stops the first page turning
    /// back.
    static func sheet<T>(
        at display: Int?,
        decoded: (Int) -> T?,
        placeholder: (Int) -> T?
    ) -> T? {
        guard let display else { return nil }
        return decoded(display) ?? placeholder(display)
    }

    /// The short side, in pixels. The shader fits the sheet to the screen, so only the
    /// ratio counts, and a small texture is a cheap upload.
    static let side = 64

    /// Width and height for a width-over-height `ratio`, with ``side`` as the short side.
    static func size(ratio: Double) -> (width: Int, height: Int) {
        let safe = ratio > 0 ? ratio : PagePlaceholder.defaultRatio
        return safe >= 1
            ? (Int((Double(side) * safe).rounded()), side)
            : (side, Int((Double(side) / safe).rounded()))
    }

    /// A sheet of `matte` at `ratio`, or `nil` when no bitmap context could be made.
    static func image(ratio: Double, matte: Color) -> CGImage? {
        let (width, height) = size(ratio: ratio)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(matte.resolve(in: EnvironmentValues()).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
