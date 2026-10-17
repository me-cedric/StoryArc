import CoreGraphics
import CoreImage
import StoryArcCore
import SwiftUI

/// A decoded page drawn with the series' image adjustments.
///
/// `comic-reader`, *Image adjustments*: brightness, contrast, greyscale and inversion are
/// compositing operations on the view, so dragging a slider is a redraw and the preview is
/// live; sharpness and the border trim change the pixels and are worked out once per page
/// and setting, off the main actor. A Mac copy of `ReaderFeature`'s `Adjusted`, `cropped`
/// and `sharpened`, which are internal to the package (parent edit, task 5.12's family).
struct AdjustedPage: View {
    let image: CGImage
    let index: Int
    let adjustments: ImageAdjustments

    @State private var processed: CGImage?

    var body: some View {
        Image(decorative: processed ?? image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .modifier(Adjusted(adjustments: adjustments))
            .task(id: PixelWork(index: index, width: image.width, crops: adjustments.cropsBorders,
                                sharpness: adjustments.sharpness)) {
                processed = await PageProcessing.processed(image, adjustments: adjustments)
            }
    }
}

/// What the pixel work depends on, so a slider that only moves brightness redoes none of it.
private struct PixelWork: Hashable {
    let index: Int
    let width: Int
    let crops: Bool
    let sharpness: Double
}

/// Brightness, contrast, greyscale and inversion, on the view.
struct Adjusted: ViewModifier {
    let adjustments: ImageAdjustments

    func body(content: Content) -> some View {
        if adjustments.isNeutral {
            content
        } else {
            let base = content
                .grayscale(adjustments.isGreyscale ? 1 : 0)
                .brightness(adjustments.brightnessOffset)
                .contrast(adjustments.contrastFactor)
            // Inverted last, so the reader's brightness is not sent the other way.
            if adjustments.isInverted { base.colorInvert() } else { base }
        }
    }
}

/// The border trim and the sharpening, which change pixels.
enum PageProcessing {
    /// The page trimmed and sharpened as asked, or `nil` when nothing changes the pixels.
    static func processed(_ image: CGImage, adjustments: ImageAdjustments) async -> CGImage? {
        guard adjustments.cropsBorders || adjustments.sharpness > 0 else { return nil }
        let crops = adjustments.cropsBorders
        let amount = adjustments.sharpness
        return await Task.detached(priority: .userInitiated) {
            sharpened(cropped(image, when: crops), by: amount)
        }.value
    }

    /// The page with its uniform white or black margin trimmed, by `BorderCrop`'s rule read
    /// off a small greyscale copy.
    static func cropped(_ image: CGImage, when isEnabled: Bool) -> CGImage {
        guard isEnabled, let small = greyThumbnail(of: image), let data = small.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return image }
        let stride = small.bytesPerRow
        let step = small.bitsPerPixel / 8
        let inset = BorderCrop.inset(width: small.width, height: small.height) { x, y in
            Int(bytes[y * stride + x * step])
        }
        guard !inset.isEmpty else { return image }
        let scale = Double(image.width) / Double(small.width)
        let rect = CGRect(
            x: Double(inset.left) * scale, y: Double(inset.top) * scale,
            width: Double(small.width - inset.left - inset.right) * scale,
            height: Double(small.height - inset.top - inset.bottom) * scale
        )
        return image.cropping(to: rect) ?? image
    }

    // One context for every page: building a `CIContext` is the expensive part, and it is thread-safe.
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func sharpened(_ image: CGImage, by amount: Double) -> CGImage {
        guard amount > 0, let filter = CIFilter(name: "CISharpenLuminance") else { return image }
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(amount * 2.5, forKey: kCIInputSharpnessKey)
        guard let output = filter.outputImage, let result = context.createCGImage(output, from: output.extent) else {
            return image
        }
        return result
    }

    private static func greyThumbnail(of image: CGImage) -> CGImage? {
        let side = 256.0
        let scale = side / Double(max(image.width, image.height))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
