import UIKit
import XCTest

/// How much ink a control is drawn with, so "inert" and "live" can be told apart by measurement.
///
/// **This exists because the two states were pixel-identical and every test passed.** The bulk
/// action capsule carries `.disabled(selection.ids.isEmpty)`, which normally dims a control by
/// lowering its foreground — but `.storyArcGlassText(.primary)` sets an explicit
/// `foregroundStyle` after it, and an explicit foreground style wins. So `.disabled` did its
/// behavioural half and nothing at all visually: 0 of 27 900 pixels differed between the
/// nought-picked and two-picked capsule in light, in dark, and 0 of 110 500 at
/// `AccessibilityXXXL`. `§3b.4`'s whole argument for showing an inert capsule — that it "says
/// what the mode is for before anything is picked" — held only for a reader who tried one.
///
/// No host test can see this. `swift test` runs with no window, so `BulkSelectionChromeTests`
/// greps source text: it can assert the `.opacity` is *declared* and in the right order, never
/// that a pixel changed. Android's twin defect is guarded by a Robolectric bitmap; on iOS the
/// device is the only place the answer exists, which is why this lives in the UI tests.
enum CapsuleInk {

    /// The mean distance of a control's pixels from its own background.
    ///
    /// **The element is photographed, not a rectangle of the screen.** `XCUIElement` conforms
    /// to `XCUIScreenshotProviding`, so this is exactly the control's pixels, cropped by XCTest
    /// from the app's frame buffer — no point-to-pixel conversion, no `StoryArcSpace`
    /// arithmetic, and no dependence on where the capsule sits. A hard-coded rectangle would
    /// have to be four rectangles (appearance × text size), and a wrong one fails *silently*:
    /// it measures the shelf and reports the capsule.
    ///
    /// The background is the region's **median** luma rather than a fixed colour, because the
    /// capsule is glass and its luminance is whichever cover is passing under it. The glass
    /// fill dominates every one of these crops in both appearances, so the median is the
    /// material and the deviation from it is the glyph.
    ///
    /// - Returns: mean `|luma − median luma|` over the crop, in 0…255. Zero for a blank crop.
    static func mass(of element: XCUIElement) -> Double {
        let image = element.screenshot().image
        guard let source = image.cgImage else { return 0 }
        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else { return 0 }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        var luma = [Double]()
        luma.reserveCapacity(width * height)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            luma.append(
                0.2126 * Double(pixels[index])
                    + 0.7152 * Double(pixels[index + 1])
                    + 0.0722 * Double(pixels[index + 2])
            )
        }
        guard !luma.isEmpty else { return 0 }
        let median = luma.sorted()[luma.count / 2]
        return luma.reduce(0) { $0 + abs($1 - median) } / Double(luma.count)
    }
}
