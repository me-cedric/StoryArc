internal import SwiftUI
internal import UIKit

internal import ReadiumNavigator
internal import StoryArcCore

// The curl over reflowable text, which is task 4.3b of `reader-theming-and-page-transitions`.
//
// `ReflowableTurn.swift` took the turn over from Readium and spent it on one raster, which is
// Fast fade. This is the second raster. The shader is the comic reader's, unchanged — the
// projection lives in `PageRoll` and `PageCurl.metal` beside this file transliterates it — so
// a reader who turns a page of prose and a reader who turns a page of a comic watch the same
// sheet roll.
//
// **What is rolled is a picture, and only while the turn runs.** `ebook-reader` keeps a
// reflowable page as live web content: text is selectable, links are followable, and a
// read-aloud voice walks the DOM. None of that survives a texture, so the texture exists for
// the length of one turn and the live page is underneath it the whole time.

extension UIView {
    /// This view as it is drawn, at the display's own scale.
    ///
    /// `page-transitions` asks the curl to raster "at display scale": a texture at one point
    /// per pixel is the page at half resolution on every device this app supports, and body
    /// text is the one content where that is unmistakable.
    ///
    /// ponytail: `drawHierarchy` rather than `WKWebView.takeSnapshot`. The navigator holds one
    /// web view per resource and swaps them at a resource boundary, so a snapshot taken
    /// through the web view would have to find the right one twice and would still miss the
    /// chrome Readium draws around it. The ceiling is that `drawHierarchy` can answer an empty
    /// image for content the compositor has not committed; every caller here reads `nil` as
    /// "no curl this time" rather than as a failure, which costs a transition and never a
    /// turn.
    ///
    /// - Parameter afterScreenUpdates: false for a page already on screen, true for one the
    ///   navigator has just moved to and that has not been committed yet.
    func raster(afterScreenUpdates: Bool) -> CGImage? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = rasterScale
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            drawHierarchy(in: bounds, afterScreenUpdates: afterScreenUpdates)
        }
        return image.cgImage
    }

    /// The scale ``raster(afterScreenUpdates:)`` draws at: this view's own screen's, which on
    /// an iPad window on an external display is not the device's.
    var rasterScale: CGFloat { window?.screen.scale ?? traitCollection.displayScale }
}

/// The rolling sheet, drawn over the navigator while a turn runs.
///
/// A `View` rather than a layer of its own, because the shader is a SwiftUI `Shader` and
/// `ReaderFeature/CurledPages.swift` already fills a rectangle with exactly this one. The
/// finger and the spring live in ``ProseCurlDriver``; this draws where they put the page.
struct ReflowableCurl: View {
    /// The page that is leaving, rastered before the navigator moved.
    let page: CGImage
    /// The page that is arriving: rastered ahead of the turn at a chapter end, or after the
    /// navigator moved inside one. `nil` until then, and the page lies flat until it comes.
    let other: CGImage?
    let isRightToLeft: Bool
    /// Signed, as the comic reader's is: 0 to 1 for a forward turn, 0 to -1 for a turn back.
    var progress: Double
    /// The scale the rasters were taken at, passed with them from the view that took them, so
    /// a texture and the scale it was made at cannot drift apart. `UIScreen.main` answered
    /// the device's scale, which is not the window's on an external display.
    let scale: CGFloat

    var body: some View {
        let sheets = Self.sheets(progress: progress, page: page, other: other)
        Rectangle().fill(
            ShaderLibrary.bundle(.module).pageCurl(
                .float(sheets.progress),
                .float(Float(PageRoll.crease)),
                .float(Float(PageRoll.shadow)),
                .float(isRightToLeft ? -1 : 1),
                .float(Float(PageRoll.back)),
                .float(Float(PageRoll.radiusMax)),
                .float(Float(PageRoll.lean)),
                .float(Float(PageRoll.rim)),
                .float2(size.width, size.height),
                // Both rasters fill the whole area: a prose page has no fit and no zoom.
                .float4(0, 0, size.width, size.height),
                .float4(0, 0, size.width, size.height),
                .image(Image(decorative: sheets.turning ?? page, scale: scale)),
                .image(Image(decorative: sheets.under ?? page, scale: scale))
            )
        )
    }

    /// Which raster turns, which lies under it, and at what forward progress.
    ///
    /// The comic reader's own choice, ``CurlTurn/sheets(progress:page:beneath:previous:)``,
    /// with the arriving page as both neighbours: a turn back rolls the arriving page in over
    /// the leaving one, which is the forward projection run on the page behind. With no
    /// arriving page yet the leaving page lies flat and whole, which is what is under the
    /// sheet, so the sheet cannot show a page that is not there.
    static func sheets(progress: Double, page: CGImage, other: CGImage?) -> CurlTurn.Sheets<CGImage> {
        CurlTurn.sheets(progress: other == nil ? 0 : progress, page: page, beneath: other, previous: other)
    }

    /// The size the shader works in, which is the raster's size in points.
    ///
    /// Read from the texture rather than from a `GeometryReader`: the overlay is sized to the
    /// navigator's bounds by the caller, and asking SwiftUI for that size again would be a
    /// second answer that can disagree with the first by a layout pass.
    var size: CGSize {
        CGSize(width: Double(page.width) / scale, height: Double(page.height) / scale)
    }
}

/// The hosting controller the overlay lives in, and the state the finger and the spring drive.
///
/// A class because the overlay outlives the call that made it, and because a
/// `UIHostingController` that nothing retains takes its view down with it.
@MainActor
final class CurlOverlay {
    private let state: Progress
    private let controller: UIHostingController<ReflowableCurlHost>

    var view: UIView { controller.view }

    /// The arriving page, once there is one. See ``ReflowableCurl/other``.
    var other: CGImage? {
        get { state.other }
        set { state.other = newValue }
    }

    /// Where the page is drawn this frame, which mid-spring is not where it is heading.
    var drawn: Double { state.stand.value }

    /// The width a whole turn is measured against, in points.
    let width: Double

    init(page: CGImage, other: CGImage?, isRightToLeft: Bool, scale: CGFloat) {
        state = Progress(other: other)
        width = Double(page.width) / scale
        controller = UIHostingController(
            rootView: ReflowableCurlHost(
                page: page, isRightToLeft: isRightToLeft, scale: scale, state: state
            )
        )
        // Opaque would letterbox the navigator's own background in wherever the raster does
        // not reach, which at a progress of zero is nowhere and at the end of the roll is
        // the whole screen.
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
    }

    /// Puts the page where the finger is, at once. No animation: an animation between finger
    /// positions is a page lagging behind it.
    func follow(_ progress: Double) {
        state.value = progress
        state.stand.value = progress
    }

    /// Springs the page to `target` and returns when the spring is done or was taken over.
    ///
    /// The comic reader's spring, ``CurlTurn/settleDuration``. SwiftUI runs the completion
    /// when the animation is removed, which a drag that takes the page over does, so the
    /// caller decides by its own ticket whether the turn is still its own to finish.
    func settle(to target: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withAnimation(.spring(duration: CurlTurn.settleDuration)) {
                state.value = target
            } completion: {
                continuation.resume()
            }
        }
    }

    /// Where the roll is heading, which page is under it, and where it is drawn this frame.
    ///
    /// Observable rather than a binding, so the hosting controller is built once and the
    /// values that change after it is on screen can change without rebuilding it.
    @MainActor
    @Observable
    final class Progress {
        var value: Double = 0
        var other: CGImage?
        /// Written on every frame of a spring, so it is not observed. See ``Curling``.
        @ObservationIgnored let stand = Stand()

        init(other: CGImage?) {
            self.other = other
        }
    }

    /// Where the roll is drawn this frame, which a drag that takes over a spring starts from.
    @MainActor
    final class Stand {
        var value: Double = 0
    }
}

/// What the hosting controller draws: the sheet, at whatever progress the roll has reached.
struct ReflowableCurlHost: View {
    let page: CGImage
    let isRightToLeft: Bool
    let scale: CGFloat
    @State var state: CurlOverlay.Progress

    var body: some View {
        Curling(progress: state.value, stand: state.stand) { drawn in
            ReflowableCurl(
                page: page,
                other: state.other,
                isRightToLeft: isRightToLeft,
                progress: drawn,
                scale: scale
            )
        }
        .ignoresSafeArea()
    }
}

/// The curl, drawn at the value SwiftUI is actually interpolating.
///
/// The comic reader's `Curling`, for the same reason: a view that conforms to `Animatable` is
/// handed every step of the spring, which is the only way to know where a settle stands, so a
/// drag that catches it can pick the page up there rather than at its destination.
private struct Curling<Content: View>: View, @MainActor Animatable {
    var progress: Double
    let stand: CurlOverlay.Stand
    @ViewBuilder let content: (Double) -> Content

    var animatableData: Double {
        get { progress }
        set {
            progress = newValue
            stand.value = newValue
        }
    }

    var body: some View { content(progress) }
}
