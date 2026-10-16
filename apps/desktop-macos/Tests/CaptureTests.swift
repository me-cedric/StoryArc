import AppKit
import Testing

@testable import StoryArc

/// Whether the frames were asked for. Outside the suite so the trait can read it.
enum CaptureRequest {
    static var isSet: Bool { ProcessInfo.processInfo.environment["STORYARC_CAPTURE"] != nil }
}

extension WindowWalks {
    /// The frames of the wave 1 shell, taken from inside the app.
    ///
    /// Why inside: `screencapture -l` needs the Screen Recording permission of the process that
    /// runs it, which an agent session does not have (task 0.10 hit the same wall). A process
    /// may image its own windows, so this suite asks the window server for the library and
    /// settings windows in light and in dark and writes PNGs into the sandbox container's
    /// `tmp/captures/`, the one place a sandboxed test can write. Copy them out from
    /// `~/Library/Containers/com.mecedric.storyarc/Data/tmp/captures/`. A `method.txt` beside
    /// them names how each frame was taken: `window-server` is the real pixels; `view-cache`
    /// is the view tree drawn in-process, which cannot show the sidebar's material.
    ///
    /// Off unless asked for, like the iOS capture classes: run with
    /// `TEST_RUNNER_STORYARC_CAPTURE=1 xcodebuild test …`. Dark is the app's own appearance,
    /// not the system's, so nothing on the machine changes.
    @MainActor
    @Suite("Captures", .enabled(if: CaptureRequest.isSet, "set TEST_RUNNER_STORYARC_CAPTURE=1 to capture"))
    struct CaptureTests {
        @Test("The library window and the settings window, light and dark, default and narrow")
        func captureShell() throws {
            let window = try #require(ShellWalk.waitForLibraryWindow())
            let folder = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
                .appending(path: "tmp/captures", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { NSApplication.shared.appearance = nil }

            let wide = NSRect(x: 80, y: 80, width: 1100, height: 720)
            let narrow = NSRect(origin: wide.origin, size: LibraryWindow.minimumSize)
            let before = ShellWalk.visibleWindows()
            ShellWalk.openSettings()
            let settings = try #require(ShellWalk.waitForNewWindow(since: before))
            // A window of an inactive app cannot become key, and a host launched by xcodebuild is
            // refused cooperative activation. Asking Launch Services to open the running app is
            // what a click on its Dock icon does, and that activation is granted.
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: .init())
            _ = ShellWalk.wait(timeout: 3) { NSApplication.shared.isActive ? true : nil }
            var methods: [String] = []

            for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                NSApplication.shared.appearance = NSAppearance(named: appearance)
                _ = ShellWalk.wait { window.effectiveAppearance.name == appearance ? true : nil }

                Self.resize(window, to: wide)
                methods.append(try Self.capture(window, to: folder.appending(path: "library-\(suffix).png")))
                // A tiling window manager (Amethyst runs on the owner's Mac) reasserts the frame
                // of every resizable window. It leaves a fixed-size window alone, so the minimum
                // is shown with the size locked for the length of one frame.
                window.styleMask.remove(.resizable)
                Self.resize(window, to: narrow)
                methods.append(try Self.capture(window, to: folder.appending(path: "library-narrow-\(suffix).png")))
                window.styleMask.insert(.resizable)
                Self.resize(window, to: wide)
                methods.append(try Self.capture(settings, to: folder.appending(path: "settings-\(suffix).png")))
            }
            settings.close()
            try methods.joined(separator: "\n").write(
                to: folder.appending(path: "method.txt"), atomically: true, encoding: .utf8
            )
        }

        /// Sets the frame and waits until the window has it.
        private static func resize(_ window: NSWindow, to frame: NSRect) {
            window.setFrame(frame, display: true)
            _ = ShellWalk.wait { window.frame.size == frame.size ? true : nil }
        }

        /// Writes the window as a PNG and says how it was imaged.
        private static func capture(_ window: NSWindow, to file: URL) throws -> String {
            // Key, or the frame shows a window nobody is using: grey traffic lights and a
            // prominent button drawn as inactive.
            window.makeKeyAndOrderFront(nil)
            _ = ShellWalk.wait(timeout: 1) { window.isKeyWindow ? true : nil }
            ShellWalk.settle()
            window.displayIfNeeded()
            let (image, method): (CGImage, String)
            if let served = WindowImage.fromWindowServer(window) {
                (image, method) = (served, "window-server")
            } else {
                (image, method) = (try #require(WindowImage.fromViewCache(window)), "view-cache")
            }
            let bitmap = NSBitmapImageRep(cgImage: image)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: file)
            #expect(image.width > 0 && image.height > 0)
            let state = "active=\(NSApplication.shared.isActive) key=\(window.isKeyWindow) frame=\(window.frame)"
            return "\(file.lastPathComponent)\t\(method)\t\(state)"
        }
    }
}

/// Two ways to image one of this process's own windows.
@MainActor
enum WindowImage {
    private typealias ListImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    /// The real pixels, from the window server.
    ///
    /// `CGWindowListCreateImage` is marked unavailable in the macOS 26 SDK and is still in
    /// CoreGraphics, so it is reached by name. `nil` when the window server refuses, which
    /// is what a missing Screen Recording grant looks like.
    static func fromWindowServer(_ window: NSWindow) -> CGImage? {
        guard let handle = dlopen(nil, RTLD_NOW), let symbol = dlsym(handle, "CGWindowListCreateImage") else {
            return nil
        }
        let function = unsafeBitCast(symbol, to: ListImage.self)
        let options = CGWindowListOption.optionIncludingWindow.rawValue
        let imageOptions: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        let image = function(.null, options, UInt32(window.windowNumber), imageOptions.rawValue)
        return image?.takeRetainedValue()
    }

    /// The view tree drawn in-process, title bar and toolbar included.
    ///
    /// The window's frame view is the content view's superview, and it is what carries
    /// the toolbar. Materials are composited by the window server, so they are absent here.
    static func fromViewCache(_ window: NSWindow) -> CGImage? {
        guard let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
