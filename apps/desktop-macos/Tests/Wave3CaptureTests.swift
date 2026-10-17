import AppKit
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The wave 3 frames: the catalogue screens wave 3 added or changed, in light and dark, at
    /// the default text size and the reader's largest. Off unless asked for, as the wave 2
    /// captures are; written to the container's `tmp/captures/wave3/`.
    /// `docs/designs/screenshots/desktop/macos/wave3/README.md` names each frame and its limits.
    @MainActor
    @Suite("Wave 3 captures", .enabled(if: CaptureRequest.isSet, "set TEST_RUNNER_STORYARC_CAPTURE=1 to capture"))
    struct Wave3CaptureTests {
        /// The screens of tasks 3.10 to 3.15a.
        static let screens: Set<String> = [
            "home", "downloads", "shelf-collection", "shelf-list",
            "settings-sources", "source-share", "source-catalogue", "source-kavita",
            "settings-downloads", "settings-privacy", "diagnostic",
        ]

        @Test("Sources, downloads, diagnostic, storage and shelves, light and dark, default and largest text")
        func captureWave3() async throws {
            let (library, reading) = try await MacCatalogue.prepare()
            library.model.dismissSkipped()
            let folder = try Walk.captureFolder("wave3")
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
                        guard Self.screens.contains(screen) else { return }
                        let file = folder.appending(path: "\(screen)-\(suffix).png")
                        methods.append(try Wave2CaptureTests.capture(window, to: file))
                    }
                }
            }
            try methods.joined(separator: "\n").write(
                to: folder.appending(path: "method.txt"), atomically: true, encoding: .utf8
            )
        }
    }
}
