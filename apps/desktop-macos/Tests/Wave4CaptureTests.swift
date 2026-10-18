import AppKit
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The wave 4 frames: the EPUB reader, the PDF selection and the player, in light and
    /// dark, at the default text size and the largest. Off unless asked for, as the wave 2
    /// and 3 captures are; written to the container's `tmp/captures/wave4/`.
    /// `docs/designs/screenshots/desktop/macos/wave4/README.md` names each frame and its limits.
    @MainActor
    @Suite("Wave 4 captures", .enabled(if: CaptureRequest.isSet, "set TEST_RUNNER_STORYARC_CAPTURE=1 to capture"))
    struct Wave4CaptureTests {
        /// The screens of tasks 4.5 to 4.8.
        static let screens: Set<String> = ["epub-reader", "pdf-selection", "player"]

        @Test("EPUB, PDF text and the player, light and dark, default and largest text")
        func captureWave4() async throws {
            let (library, reading) = try await MacCatalogue.prepare()
            library.model.dismissSkipped()
            let folder = try Walk.captureFolder("wave4")
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
