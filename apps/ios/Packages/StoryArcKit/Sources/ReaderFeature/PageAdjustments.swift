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
