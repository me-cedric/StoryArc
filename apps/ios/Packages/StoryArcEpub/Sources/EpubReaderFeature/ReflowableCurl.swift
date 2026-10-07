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
/// `ReaderFeature/CurledPages.swift` already fills a rectangle with exactly this one. There is
/// no gesture here and no spring: a reflowable turn is discrete — a tap, a key, a released
/// swipe — and `progress` is driven by the animation the caller starts.
struct ReflowableCurl: View {
    /// The page that is leaving, rastered before the navigator moved.
    let page: CGImage
    /// The page that is arriving, rastered after it moved and before this was shown.
    let beneath: CGImage
    let isRightToLeft: Bool
    var progress: Double
    /// The scale the rasters were taken at, passed with them from the view that took them, so
    /// a texture and the scale it was made at cannot drift apart. `UIScreen.main` answered
    /// the device's scale, which is not the window's on an external display.
    let scale: CGFloat

    var body: some View {
        Rectangle().fill(
            ShaderLibrary.bundle(.module).pageCurl(
                .float(progress),
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
                .image(Image(decorative: page, scale: scale)),
                .image(Image(decorative: beneath, scale: scale))
            )
        )
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

extension EpubReaderModel {

    /// How long one curl takes. The comic reader's spring settles in about this, and a turn
    /// of prose that took longer would read as the page having stuck.
    static let curlDuration = 0.34

    /// Turns a page by rolling a picture of it off a picture of the next one.
    ///
    /// The order is the whole trick, and it is one navigator move rather than three:
    ///
    /// 1. the outgoing page is rastered while it is still on screen;
    /// 2. the overlay goes up at a progress of zero, where the shader draws that raster flat
    ///    and whole — so the overlay is indistinguishable from the page under it;
    /// 3. the navigator moves with no animation of its own, hidden under the overlay;
    /// 4. the page that arrived is rastered and becomes the sheet beneath;
    /// 5. the roll runs, and the overlay comes off, leaving the live page it was hiding.
    ///
    /// **The overlay is added to the navigator view's superview, not to the navigator view.**
    /// Step 4 rasters the navigator, and an overlay inside it would be in that picture — the
    /// turn would then roll the outgoing page off a photograph of itself.
    ///
    /// A raster that does not arrive leaves the turn as a cut: the navigator has already
    /// moved by then, so the reader loses the transition and never the page.
    func turnWithCurl(forward: Bool) async {
        guard let navigator, let page = navigator.view, let host = page.superview,
              let outgoing = page.raster(afterScreenUpdates: false)
        else {
            await plainTurn(forward: forward)
            return
        }

        let curl = CurlOverlay(
            page: outgoing,
            // Stood in by the outgoing page until step 4 has one. The shader samples it only
            // past the fold, and at a progress of zero there is no past the fold.
            beneath: outgoing,
            isRightToLeft: isRightToLeft,
            scale: page.rasterScale
        )
        curl.view.frame = page.frame
        host.addSubview(curl.view)

        let moved = forward
            ? await navigator.goForward(options: NavigatorGoOptions(animated: false))
            : await navigator.goBackward(options: NavigatorGoOptions(animated: false))

        guard moved, let incoming = page.raster(afterScreenUpdates: true) else {
            // At the end of the book, or with nothing to photograph. Both go at once rather
            // than rolling, because a roll onto the page it started from reads as a turn that
            // did not happen.
            curl.view.removeFromSuperview()
            return
        }

        curl.beneath = incoming
        await curl.roll(over: Self.curlDuration)
        curl.view.removeFromSuperview()
    }

    /// Readium's own turn, for the branches above that have no curl to draw.
    private func plainTurn(forward: Bool) async {
        if forward { await goForward() } else { await goBackward() }
    }
}

/// The hosting controller the overlay lives in, and the one piece of state the roll drives.
///
/// A class because the overlay outlives the call that made it by exactly one animation, and
/// because a `UIHostingController` that nothing retains takes its view down with it.
@MainActor
final class CurlOverlay {
    private let state: Progress
    private let controller: UIHostingController<ReflowableCurlHost>

    var view: UIView { controller.view }

    var beneath: CGImage {
        get { state.beneath }
        set { state.beneath = newValue }
    }

    init(page: CGImage, beneath: CGImage, isRightToLeft: Bool, scale: CGFloat) {
        state = Progress(beneath: beneath)
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

    /// Runs the roll and returns when it has finished.
    func roll(over duration: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withAnimation(.easeInOut(duration: duration)) {
                state.value = 1
            } completion: {
                continuation.resume()
            }
        }
    }

    /// Where the roll stands, and which page is under it.
    ///
    /// Observable rather than a binding, so the hosting controller is built once and the two
    /// values that change after it is on screen can change without rebuilding it.
    @MainActor
    @Observable
    final class Progress {
        var value: Double = 0
        var beneath: CGImage

        init(beneath: CGImage) {
            self.beneath = beneath
        }
    }
}

/// What the hosting controller draws: the sheet, at whatever progress the roll has reached.
struct ReflowableCurlHost: View {
    let page: CGImage
    let isRightToLeft: Bool
    let scale: CGFloat
    @State var state: CurlOverlay.Progress

    var body: some View {
        ReflowableCurl(
            page: page,
            beneath: state.beneath,
            isRightToLeft: isRightToLeft,
            progress: state.value,
            scale: scale
        )
        .ignoresSafeArea()
    }
}
