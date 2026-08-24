public import CoreGraphics
public import Foundation

internal import ImageIO

/// Decoding a page's bytes into something drawable.
///
/// ADR-0005 chose the platform decoder rather than a library: ImageIO on Apple,
/// `ImageDecoder` on Android. Between them they cover the only three things the
/// reader needs — decode from bytes, downsample to a target size, and re-decode
/// larger when the user zooms — and keeping both platforms on their own system
/// decoder keeps the two paths structurally alike.
public enum PageDecoder {
    public enum DecodeError: Error, Equatable {
        /// The bytes are not an image ImageIO recognises.
        case unrecognised
        /// Recognised, but the decode itself failed — truncated data, usually.
        case failed
    }

    /// A page's pixel dimensions, read from the image header without decoding it.
    ///
    /// Cheap enough to call while indexing thousands of pages: it reads the
    /// header, not the pixels. `comic-reader` needs this to detect double-page
    /// spreads and to size a placeholder at the correct aspect ratio before the
    /// page itself has arrived.
    public static func dimensions(of data: Data) throws -> CGSize {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw DecodeError.unrecognised
        }
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            throw DecodeError.unrecognised
        }
        return CGSize(width: width, height: height)
    }

    /// Decodes at most `maxPixelSize` on the longest edge.
    ///
    /// Passing the display's need rather than `nil` is the difference between a
    /// 2000×3000 page costing 24 MB of pixels and costing what it is shown at —
    /// which is what `publication-formats` means by downsampling a page too
    /// large for the device.
    public static func decode(_ data: Data, maxPixelSize: Int? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw DecodeError.unrecognised
        }

        guard let maxPixelSize else {
            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw DecodeError.failed
            }
            return image
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            // Without this the thumbnail comes back unscaled when the source
            // carries no embedded preview, which silently defeats the point.
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw DecodeError.failed
        }
        return image
    }

    /// Whether a page is a double-page spread.
    ///
    /// `comic-reader` requires a materially wider-than-tall page in a portrait
    /// publication to be shown alone rather than split across two turns. The
    /// threshold is deliberately generous: a page that is merely a little wide is
    /// not a spread, and guessing wrong is worse than not guessing.
    public static func isSpread(_ size: CGSize, threshold: CGFloat = 1.2) -> Bool {
        guard size.height > 0 else { return false }
        return size.width / size.height >= threshold
    }
}
