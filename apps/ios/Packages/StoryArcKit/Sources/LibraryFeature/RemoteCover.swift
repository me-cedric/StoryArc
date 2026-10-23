import Formats
import SwiftUI

/// A server's cover for one cell: decoded off the main actor, and no larger than it is drawn.
///
/// Four cells decoded every server cover whole, on the main actor, with `UIImage(data:)`.
/// This goes through the same thumbnail path `CoverLadder` uses for a chosen cover, so a
/// 2000 by 3000 picture costs what the cell shows rather than 24 MB of pixels per cell.
enum RemoteCover {
    /// `data` with its longer side at most `maxPixelSize`, or nil for bytes that are not a
    /// picture this device can decode. Nil is a normal state: every caller leaves the frame
    /// empty for it.
    static func decoded(_ data: Data, maxPixelSize: Int) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            try? PageDecoder.decode(data, maxPixelSize: maxPixelSize)
        }.value
    }

    /// ``decoded(_:maxPixelSize:)`` as a SwiftUI image. Decorative: the cell around it
    /// carries the label, as it did when the image came from `UIImage(data:)`.
    static func image(from data: Data, maxPixelSize: Int) async -> Image? {
        await decoded(data, maxPixelSize: maxPixelSize).map { Image(decorative: $0, scale: 1) }
    }
}
