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
    _ screen: some View, mode: AppearanceMode, style: UIUserInterfaceStyle, for seconds: TimeInterval
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

/// Light and dark, one image each, from one view and its fixture state.
///
/// A reference is `__Snapshots__/<class>/<slug>.<light|dark>.png`, so the catalogue number and
/// name in `docs/designs/screen-catalogue.md` find the file. Setting
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
    for (name, mode, style) in [
        ("light", AppearanceMode.light, UIUserInterfaceStyle.light),
        ("dark", AppearanceMode.dark, UIUserInterfaceStyle.dark),
    ] {
        assertSnapshot(
            of: draw(view, mode: mode, style: style, for: max(delay, settleSeconds)),
            as: .image(precision: precision, perceptualPrecision: 0.98, scale: 2),
            named: name,
            file: file,
            testName: slug,
            line: line
        )
    }
}
