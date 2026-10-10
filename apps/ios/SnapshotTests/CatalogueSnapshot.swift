import DesignSystem
import SnapshotTesting
import StoryArcCore
import SwiftUI
import UIKit
import XCTest

/// The iPhone 17 Pro and the iPhone 17 share one size: 402 by 874 points, drawn at scale 2.
private let phoneSize = CGSize(width: 402, height: 874)

/// How long a screen has to settle. Glass animates its edge and its highlight for about two
/// seconds after it appears, and an image drawn earlier differs from run to run in that edge.
private let settleSeconds: TimeInterval = 3

/// Draws the screen the way the display shows it.
///
/// The screen goes into a window of the host app's own scene. The library's view strategy
/// renders with `CALayer.render(in:)`, the CPU path, which leaves out Liquid Glass, blurs and
/// every other effect the render server draws; a window in a real scene is drawn with
/// `drawHierarchy`, which asks the render server. The run loop turns before the draw so each
/// `.task` and `.onAppear` has run: the library's `.wait` waits before the view is in a window,
/// where no task starts.
@MainActor
private func draw(
    _ screen: some View,
    mode: AppearanceMode,
    style: UIUserInterfaceStyle,
    for seconds: TimeInterval,
    textSize: UIContentSizeCategory? = nil
) -> UIImage {
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
        fatalError("The snapshot tests run hosted in the app, which has a window scene.")
    }
    precondition(
        scene.screen.bounds.size == phoneSize,
        "The catalogue is drawn on an iPhone 17 or 17 Pro (402 by 874), not \(scene.screen.bounds.size)."
    )
    let host = UIHostingController(rootView: screen.storyArcTheme(appearance: mode))
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(origin: .zero, size: phoneSize)
    window.windowLevel = .alert + 1
    window.overrideUserInterfaceStyle = style
    if let textSize {
        // A trait of the window, so the SwiftUI views and the UIKit bars both read it.
        window.traitOverrides.preferredContentSizeCategory = textSize
    }
    window.rootViewController = host
    window.makeKeyAndVisible()
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    window.layoutIfNeeded()
    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    // Standard range keeps the file 8-bit sRGB. The default is the display's extended range, a
    // 16-bit PNG that is four times the size and says no more about a screen drawn in sRGB.
    format.preferredRange = .standard
    let image = UIGraphicsImageRenderer(size: phoneSize, format: format).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    window.isHidden = true
    window.rootViewController = nil
    return image
}

/// Light and dark at the default text size, and light at the largest text size, one image each,
/// from one view and its fixture state.
///
/// A reference is `__Snapshots__/<class>/<slug>.<light|dark|largest>.png`, so the catalogue
/// number and name in `docs/designs/screen-catalogue.md` find the file. The largest size is the
/// last accessibility size, AX5 (`lighter-visual-check`, "Both appearances"). Setting
/// `TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all` records again, which `pnpm snap:ios:record` does.
@MainActor
func assertCatalogue<Screen: View>(
    _ slug: String,
    delay: TimeInterval = 0,
    precision: Float = 0.99,
    file: StaticString = #filePath,
    line: UInt = #line,
    @ViewBuilder _ screen: () -> Screen
) {
    NSTimeZone.default = .gmt
    let view = screen()
    for name in ["light", "dark", "largest"] {
        let isDark = name == "dark"
        let textSize: UIContentSizeCategory? = name == "largest" ? .accessibilityExtraExtraExtraLarge : nil
        let image = draw(
            view,
            mode: isDark ? .dark : .light,
            style: isDark ? .dark : .light,
            for: max(delay, settleSeconds),
            textSize: textSize
        )
        assertSnapshot(
            of: image,
            as: .image(precision: precision, perceptualPrecision: 0.98, scale: 2),
            named: name,
            file: file,
            testName: slug,
            line: line
        )
    }
}

/// One appearance of a screen, drawn the way `assertCatalogue` draws it, for a test that
/// measures the picture instead of comparing it.
@MainActor
func drawnCatalogue(_ screen: some View, dark: Bool, delay: TimeInterval = 0) -> UIImage {
    draw(
        screen, mode: dark ? .dark : .light, style: dark ? .dark : .light, for: max(delay, settleSeconds)
    )
}

/// The WCAG contrast between a run of text and what is behind it, measured in `rect` (points).
///
/// The background is the median luminance of the region, and the text is its extreme: the darkest
/// pixel when `textIsDarker`, the lightest otherwise. A glyph's stroke is a solid colour at its
/// centre, so the extreme is the colour the text was drawn in.
func textContrast(in image: UIImage, rect: CGRect, textIsDarker: Bool) -> Double {
    guard let cgImage = image.cgImage else { return 0 }
    let scale = CGFloat(cgImage.width) / phoneSize.width
    var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
    guard let context = CGContext(
        data: &pixels, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8,
        bytesPerRow: cgImage.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return 0 }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    func linear(_ value: UInt8) -> Double {
        let unit = Double(value) / 255
        return unit <= 0.03928 ? unit / 12.92 : pow((unit + 0.055) / 1.055, 2.4)
    }
    var luminances: [Double] = []
    for row in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
        for column in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
            let offset = (row * cgImage.width + column) * 4
            let red = linear(pixels[offset])
            let green = linear(pixels[offset + 1])
            let blue = linear(pixels[offset + 2])
            luminances.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
        }
    }
    luminances.sort()
    guard let text = textIsDarker ? luminances.first : luminances.last else { return 0 }
    let background = luminances[luminances.count / 2]
    return (max(text, background) + 0.05) / (min(text, background) + 0.05)
}

/// The box, in points, that what a view draws covers on a white page: what a reader sees of a
/// control, not the room the layout gave it.
///
/// A frame or a touch area is invisible here, so this is how a test asks whether a hit region
/// changed the drawn size of a control.
@MainActor
func drawnBounds(of view: some View) -> CGRect {
    let page = ZStack(alignment: .topLeading) {
        Color.white.ignoresSafeArea()
        view.padding(20)
    }
    guard let image = draw(page, mode: .light, style: .light, for: 1).cgImage else { return .null }
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return .null }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    var box = CGRect.null
    for row in 0..<height {
        for column in 0..<width {
            let offset = (row * width + column) * 4
            // Anything but white, with a few levels of slack for the dithering of a fill.
            if pixels[offset] < 250 || pixels[offset + 1] < 250 || pixels[offset + 2] < 250 {
                box = box.union(CGRect(x: column, y: row, width: 1, height: 1))
            }
        }
    }
    let scale = CGFloat(image.width) / phoneSize.width
    return CGRect(
        x: box.minX / scale, y: box.minY / scale, width: box.width / scale, height: box.height / scale
    )
}
