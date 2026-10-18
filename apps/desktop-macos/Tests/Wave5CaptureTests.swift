import AppKit
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The wave 5 frames of task 5.11: Home and the Appearance tab with the brand accent and
    /// with the system accent, light and dark, and the reader and the Reading tab with the edge
    /// click zones on. Off unless asked for; written to the container's `tmp/captures/wave5/`.
    /// `docs/designs/screenshots/desktop/macos/wave5/README.md` names each frame and its limits.
    @MainActor
    @Suite("Wave 5 captures", .enabled(if: CaptureRequest.isSet, "set TEST_RUNNER_STORYARC_CAPTURE=1 to capture"))
    struct Wave5CaptureTests {
        static let accentScreens: Set<String> = ["home", "settings-appearance"]
        static let zoneScreens: Set<String> = ["reader", "settings-reading"]

        @Test("Both accents in light and dark, and a reader with the click zones on")
        func captureWave5() async throws {
            let (library, reading) = try await MacCatalogue.prepare()
            library.model.dismissSkipped()
            let folder = try Walk.captureFolder("wave5")
            let settings = MacSettings.shared
            let accent = settings.accent
            let zones = settings.settings.turnPagesByTappingTheEdges
            defer {
                NSApplication.shared.appearance = nil
                settings.accent = accent
                settings.settings.turnPagesByTappingTheEdges = zones
            }
            settings.settings.turnPagesByTappingTheEdges = true
            var methods: [String] = []
            for (appearance, scheme) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                NSApplication.shared.appearance = NSAppearance(named: appearance)
                for choice in ChromeAccent.allCases {
                    settings.accent = choice
                    try await MacCatalogue.walk(library: library, reading: reading) { screen, window in
                        let name: String
                        if Self.accentScreens.contains(screen) {
                            name = "\(screen)-accent-\(choice.rawValue)-\(scheme)"
                        } else if Self.zoneScreens.contains(screen), choice == .brand {
                            name = "\(screen)-zones-on-\(scheme)"
                        } else {
                            return
                        }
                        methods.append(try Wave2CaptureTests.capture(window, to: folder.appending(path: "\(name).png")))
                    }
                }
            }
            #expect(methods.count == 12)
            try methods.joined(separator: "\n").write(
                to: folder.appending(path: "method.txt"), atomically: true, encoding: .utf8
            )
        }
    }
}
