internal import CoreGraphics
internal import CoreImage
internal import SwiftUI

internal import StoryArcCore

/// Applies what the reader asked for to whatever is drawn below.
///
/// `comic-reader` wants brightness, contrast, colour inversion and greyscale "with a live
/// preview". All four are compositing operations the GPU already does for free, so they go on
/// the view rather than through the image: no decode is repeated, and dragging a slider costs
/// a redraw rather than a re-render.
///
/// Sharpness is the exception and is handled by ``sharpened(_:by:)``, because sharpening is a
/// convolution and SwiftUI has no modifier for one.
struct Adjusted: ViewModifier {
    let adjustments: ImageAdjustments

    func body(content: Content) -> some View {
        if adjustments.isNeutral {
            // Nothing asked for, nothing inserted. A neutral filter chain still costs an
            // offscreen pass on every page of every comic, which is most of the time.
            content
        } else {
            adjust(content)
        }
    }

    @ViewBuilder
    private func adjust(_ content: Content) -> some View {
        let base = content
            .grayscale(adjustments.isGreyscale ? 1 : 0)
            .brightness(adjustments.brightnessOffset)
            .contrast(adjustments.contrastFactor)
        if adjustments.isInverted {
            // Last, so the reader's brightness and contrast are what they see rather than
            // their opposites: inverting first would send a brightened page darker.
            base.colorInvert()
        } else {
            base
        }
    }
}

extension View {
    /// Draws this in the state the reader chose for the series.
    func adjusted(_ adjustments: ImageAdjustments) -> some View {
        modifier(Adjusted(adjustments: adjustments))
    }
}

/// The same page with its uniform margin gone, or the same page when there was none.
///
/// `comic-reader`: "uniform white or black margins are detected and trimmed per page". Per
/// page is the requirement and also the only thing that works -- a scan's margin varies from
/// sheet to sheet, and one inset applied to a whole comic crops half of it wrongly.
///
/// The detection reads a thumbnail rather than the page. A margin is uniform by definition,
/// so it survives being scaled down, and reading two million pixels on every page turn is
/// the difference between a reader who notices and one who does not.
func cropped(_ image: CGImage, when isEnabled: Bool) -> CGImage {
    guard isEnabled else { return image }
    guard let small = thumbnail(of: image), let data = small.dataProvider?.data,
          let bytes = CFDataGetBytePtr(data)
    else { return image }

    let stride = small.bytesPerRow
    let step = small.bitsPerPixel / 8
    let inset = BorderCrop.inset(width: small.width, height: small.height) { x, y in
        // The red channel alone. A margin is grey by definition -- white or black -- so the
        // other two say the same thing, and asking for one is a third of the work.
        Int(bytes[y * stride + x * step])
    }
    guard !inset.isEmpty else { return image }

    // Back up to the page's own scale, which is what the crop has to be expressed in.
    let scale = Double(image.width) / Double(small.width)
    let rect = CGRect(
        x: Double(inset.left) * scale,
        y: Double(inset.top) * scale,
        width: Double(small.width - inset.left - inset.right) * scale,
        height: Double(small.height - inset.top - inset.bottom) * scale
    )
    return image.cropping(to: rect) ?? image
}

/// A small greyscale copy, laid out so a byte can be read straight out of it.
private func thumbnail(of image: CGImage) -> CGImage? {
    let side = 256
    let scale = Double(side) / Double(max(image.width, image.height))
    let size = (
        width: max(1, Int(Double(image.width) * scale)),
        height: max(1, Int(Double(image.height) * scale))
    )
    guard let context = CGContext(
        data: nil,
        width: size.width,
        height: size.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return nil }
    context.interpolationQuality = .low
    context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
    return context.makeImage()
}

/// One shared context. Building a `CIContext` per page is the expensive part of CoreImage,
/// not the filter.
private let sharpeningContext = CIContext(options: [.useSoftwareRenderer: false])

/// The same page with its edges brought back, or the same page when nothing was asked for.
///
/// `CISharpenLuminance` rather than an unsharp mask: it works on luminance alone, so a
/// colour scan does not gain fringes along every line, which is the usual complaint about
/// sharpening comic art.
///
/// Returns the original on any failure. A page that will not sharpen is still a page, and a
/// reader who moved a slider would rather see less than nothing.
func sharpened(_ image: CGImage, by amount: Double) -> CGImage {
    guard amount > 0 else { return image }
    let filter = CIFilter(name: "CISharpenLuminance")
    filter?.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
    // 0…2.5 covers "slightly crisper" to "as far as this is worth taking", measured on the
    // fixture scans. Past that the filter finds noise rather than lines.
    filter?.setValue(amount * 2.5, forKey: kCIInputSharpnessKey)
    guard let output = filter?.outputImage,
          let result = sharpeningContext.createCGImage(output, from: output.extent)
    else { return image }
    return result
}
