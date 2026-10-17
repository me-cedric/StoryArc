import AppKit
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The wave 2 frames: every screen of the Mac's catalogue (`MacCatalogue`), in light and
    /// dark, at the default text size and the reader's largest, over the fixture library. Off
    /// unless asked for, as `CaptureTests` is; written to the container's `tmp/captures/wave2/`.
    /// `docs/designs/screenshots/desktop/macos/wave2/README.md` names each frame and its limits.
    ///
    /// The snapshot tests walk the same screens and draw them in-process; these ask the window
    /// server, so they hold the glass and the sidebar's material the snapshots cannot.
    @MainActor
    @Suite("Wave 2 captures", .enabled(if: CaptureRequest.isSet, "set TEST_RUNNER_STORYARC_CAPTURE=1 to capture"))
    struct Wave2CaptureTests {
        @Test("Library, detail, reader and preferences, light and dark, default and largest text")
        func captureWave2() async throws {
            let (library, reading) = try await MacCatalogue.prepare()
            let folder = try Walk.captureFolder("wave2")
            defer {
                NSApplication.shared.appearance = nil
                MacSettings.shared.textSize = .default
            }
            var methods: [String] = []
            for (appearance, scheme) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                for size in [ChromeTextSize.default, .largest] {
                    NSApplication.shared.appearance = NSAppearance(named: appearance)
                    MacSettings.shared.textSize = size
                    let suffix = size == .default ? scheme : "\(scheme)-largest"
                    try await MacCatalogue.walk(library: library, reading: reading) { screen, window in
                        methods.append(try Self.capture(window, to: folder.appending(path: "\(screen)-\(suffix).png")))
                    }
                }
            }
            try methods.joined(separator: "\n").write(
                to: folder.appending(path: "method.txt"), atomically: true, encoding: .utf8
            )
        }

        /// Writes the window as a PNG and says how it was imaged.
        private static func capture(_ window: NSWindow, to file: URL) throws -> String {
            window.makeKeyAndOrderFront(nil)
            ShellWalk.settle()
            window.displayIfNeeded()
            let (image, method): (CGImage, String)
            if let served = WindowImage.fromWindowServer(window) {
                (image, method) = (served, "window-server")
            } else {
                (image, method) = (try #require(WindowImage.fromViewCache(window)), "view-cache")
            }
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: file)
            return "\(file.lastPathComponent)\t\(method)\tactive=\(NSApplication.shared.isActive) frame=\(window.frame)"
        }
    }
}
