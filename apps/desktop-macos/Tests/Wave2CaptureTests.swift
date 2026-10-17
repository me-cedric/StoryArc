import AppKit
import Persistence
import StoryArcCore
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The wave 2 frames: every screen of the library, the reader and the preferences, in
    /// light and dark, at the default text size and the reader's largest, over the fixture
    /// library. Off unless asked for, as `CaptureTests` is; written to the container's
    /// `tmp/captures/wave2/`. `docs/designs/screenshots/desktop/macos/wave2/README.md` names
    /// each frame and its limits.
    @MainActor
    @Suite("Wave 2 captures", .enabled(if: CaptureRequest.isSet, "set TEST_RUNNER_STORYARC_CAPTURE=1 to capture"))
    struct Wave2CaptureTests {
        static let librarySize = NSRect(x: 80, y: 80, width: 1100, height: 720)
        static let readerSize = NSRect(x: 120, y: 60, width: 980, height: 820)

        @Test("Library, detail, reader and preferences, light and dark, default and largest text")
        func captureWave2() async throws {
            let library = try await Walk.fixtureLibrary()
            let window = try #require(ShellWalk.waitForLibraryWindow())
            let folder = try Walk.captureFolder("wave2")
            let reading = try #require(Walk.publication(named: "natural-sort", in: library))
            try await Self.seedHistory(reading, in: library)
            _ = try? await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init())
            _ = await Walk.until(.seconds(3)) { NSApplication.shared.isActive ? true : nil }
            defer {
                NSApplication.shared.appearance = nil
                MacSettings.shared.textSize = .default
                library.model.layout = .grid
            }
            var methods: [String] = []

            for (appearance, scheme) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                for size in [ChromeTextSize.default, .largest] {
                    NSApplication.shared.appearance = NSAppearance(named: appearance)
                    MacSettings.shared.textSize = size
                    let suffix = size == .default ? scheme : "\(scheme)-largest"
                    methods += try await Self.library(
                        window, library: library, reading: reading, folder: folder, suffix: suffix
                    )
                    methods += try await Self.reader(library: library, reading: reading, folder: folder, suffix: suffix)
                    methods += try await Self.settings(folder: folder, suffix: suffix)
                }
            }
            try methods.joined(separator: "\n").write(
                to: folder.appending(path: "method.txt"), atomically: true, encoding: .utf8
            )
        }

        /// A position partway through one publication, so Home has a Keep reading shelf.
        private static func seedHistory(_ publication: Publication, in library: MacLibrary) async throws {
            let store = try #require(library.progress)
            try await store.save(ReadingProgress(
                identity: publication.identity, position: .page(index: 4, of: 12), updatedAt: Date()
            ))
            await library.refreshProgress()
        }

        private static func library(
            _ window: NSWindow, library: MacLibrary, reading: Publication, folder: URL, suffix: String
        ) async throws -> [String] {
            var methods: [String] = []
            let steps: [(String, () -> Void)] = [
                ("home", { library.navigationRequest = .go(.home) }),
                ("library-grid", { library.model.layout = .grid; library.navigationRequest = .go(.library) }),
                ("library-list", { library.model.layout = .list }),
                ("search", { library.model.layout = .grid; library.navigationRequest = .search("sort") }),
                ("detail", {
                    library.navigationRequest = .go(.library)
                }),
            ]
            for (name, step) in steps {
                step()
                if name == "detail" {
                    try await Task.sleep(for: .milliseconds(500))
                    library.navigationRequest = .details(publicationID: reading.id)
                }
                try await Task.sleep(for: .milliseconds(900))
                let file = folder.appending(path: "\(name)-\(suffix).png")
                methods.append(try capture(window, at: librarySize, to: file))
            }
            library.navigationRequest = .search("")
            try await Task.sleep(for: .milliseconds(300))
            // Library keeps its pushed page now (each row remembers); the next pass starts at its root.
            library.navigationRequest = .root
            try await Task.sleep(for: .milliseconds(300))
            library.navigationRequest = .go(.home)
            return methods
        }

        private static func reader(
            library: MacLibrary, reading: Publication, folder: URL, suffix: String
        ) async throws -> [String] {
            let target = try #require(library.target(for: reading))
            try Walk.open(target)
            let window = try #require(await Walk.until { Walk.readerWindows(for: target).first })
            // Opened, decoded, and the chrome still up: it hides three seconds after opening.
            try await Task.sleep(for: .milliseconds(1200))
            let method = try capture(window, at: readerSize, to: folder.appending(path: "reader-\(suffix).png"))
            await Walk.close([window])
            return [method]
        }

        private static func settings(folder: URL, suffix: String) async throws -> [String] {
            let before = ShellWalk.visibleWindows()
            ShellWalk.openSettings()
            let window = try #require(await Walk.until { ShellWalk.visibleWindows().first { !before.contains($0) } })
            var methods: [String] = []
            for tab in [SettingsTab.appearance, .reading] {
                MacSettings.shared.settingsTab = tab
                try await Task.sleep(for: .milliseconds(600))
                let file = folder.appending(path: "settings-\(tab.rawValue)-\(suffix).png")
                methods.append(try capture(window, at: nil, to: file))
            }
            MacSettings.shared.settingsTab = .sources
            window.close()
            return methods
        }

        /// Writes the window as a PNG at a fixed size, and says how it was imaged.
        ///
        /// The size is held with the window made non-resizable for the length of the frame,
        /// because a tiling window manager otherwise fills the screen with it.
        private static func capture(_ window: NSWindow, at frame: NSRect?, to file: URL) throws -> String {
            let wasResizable = window.styleMask.contains(.resizable)
            if let frame {
                window.styleMask.remove(.resizable)
                window.setFrame(frame, display: true)
            }
            defer { if wasResizable { window.styleMask.insert(.resizable) } }
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
