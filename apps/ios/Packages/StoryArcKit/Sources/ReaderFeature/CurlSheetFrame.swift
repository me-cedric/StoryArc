internal import CoreGraphics
internal import SwiftUI

internal import StoryArcCore

// What the curl needs from the page body it stands over (D33, task 8.16).
//
// At rest the curl container draws the reader's normal page body: the fit, the pinch and the
// PDF marks. The shader is shown only while a turn runs, and it has to start and end on the
// page the body draws, or every turn jumps at both ends. These are the pieces that make the
// two agree.

/// The finger on a page in Curl, handed down to the page body that owns the touch.
///
/// The drag moved into the page's own pan recogniser (`ZoomablePageSwipe.swift`) because a
/// second recogniser over the zoomable scroll view competes with it, and a zoomed page has to
/// pan rather than turn. A class rather than a struct, so the environment sees one identity
/// for the life of the curl and the closures inside can change on every pass without
/// invalidating every view that reads it.
@MainActor
final class CurlDrag {
    enum Phase: Equatable {
        /// The drag was recognised, `travel` points across from where the finger landed.
        case began(travel: Double)
        case changed(travel: Double)
        /// The finger lifted or the touch was cancelled, with its velocity in points per
        /// second. A cancelled touch reports zero.
        case ended(travel: Double, velocity: Double)
    }

    /// What the curl does with each phase. Replaced on every pass of the curl's body, so it
    /// never answers with a page the reader has already turned.
    var handle: (Phase) -> Void = { _ in }

    /// Where the page body draws the page now, in window coordinates, or `nil` where no
    /// zoomable page is on screen. Set by the page body, read when a turn starts.
    var sheet: () -> CGRect? = { nil }

    /// Whether a SwiftUI drag has begun, for ``follow(_:)``.
    private var isFollowing = false

    /// One reading of a SwiftUI drag, which reports no phases of its own. A page that has
    /// not decoded has no scroll view to own the pan, so it drags through this instead.
    func follow(_ travel: Double) {
        handle(isFollowing ? .changed(travel: travel) : .began(travel: travel))
        isFollowing = true
    }

    /// The end of a drag that ``follow(_:)`` began.
    func end(travel: Double, velocity: Double) {
        isFollowing = false
        handle(.ended(travel: travel, velocity: velocity))
    }
}

extension EnvironmentValues {
    /// The curl's drag, or `nil` outside Curl. See ``CurlDrag``.
    @Entry var curlDrag: CurlDrag?
}

/// Where a sheet will be drawn when it lies flat.
enum CurlSheetFrame {

    /// The rectangle a page opens in, the same one ``ScrollingPage`` gives its image view.
    ///
    /// The image view is the scroll view's bounds times the zoom, and the page is fitted
    /// inside it. So a page that opens at fit-to-width is a rectangle as wide as the screen
    /// times that fit's scale, at the top, and the shader fits the page inside it exactly as
    /// the image view does. Without this a turn ended at fit-to-screen and the page jumped to
    /// its fit the moment the turn let go.
    static func opening(
        imageSize: CGSize,
        viewport: CGSize,
        fit: PageFit,
        carried: Double?,
        isRightToLeft: Bool
    ) -> CGRect {
        let owed = OwedFit(
            pageID: "",
            mode: fit,
            imageSize: imageSize,
            viewport: viewport,
            carried: carried.map { CGFloat($0) },
            isRightToLeft: isRightToLeft
        )
        let scale = max(owed.scale(upTo: OwedFit.zoomCeiling), 1)
        let content = CGSize(width: viewport.width * scale, height: viewport.height * scale)
        guard owed.opensAtTheTop else {
            return CGRect(
                x: (viewport.width - content.width) / 2,
                y: (viewport.height - content.height) / 2,
                width: content.width,
                height: content.height
            )
        }
        let x = openingXOffset(
            contentWidth: content.width,
            boundsWidth: viewport.width,
            fittedWidth: fitted(imageSize, in: viewport).width,
            isRightToLeft: isRightToLeft
        )
        return CGRect(x: -x, y: 0, width: content.width, height: content.height)
    }

    /// A sheet with nothing on it, for the shader to sample past the fold when the end screen
    /// lies beneath. The shader returns it as transparent, and the end screen shows through.
    static let clear: CGImage? = {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }()
}

/// The turning sheet's outline, as a shape the matte is clipped to. See
/// ``CurlTurn/sheetOutline(width:height:progress:isRightToLeft:steps:)``.
struct CurlSheetShape: Shape {
    var progress: Double
    let isRightToLeft: Bool

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addLines(
                CurlTurn.sheetOutline(
                    width: rect.width, height: rect.height, progress: progress, isRightToLeft: isRightToLeft
                )
            )
            path.closeSubpath()
        }
    }
}
