import AppKit
import LibraryFeature
import StoryArcCore
import Testing

@testable import StoryArc

/// Every suite that opens, closes or images the app's windows, one after another.
///
/// Swift Testing runs suites in parallel, and a walk that opens two reader windows while the
/// shell suite counts windows makes both wrong. Nested here, they take turns.
@MainActor
@Suite("Window walks", .serialized)
struct WindowWalks {}

/// The fixture library and the waits the walks share.
///
/// Waits are `await`ed rather than spun on the run loop: a library scan and a reader's page
/// decode hop back to the main actor, and a synchronous spin inside a main-actor test holds
/// those hops back until it gives up.
@MainActor
enum Walk {
    /// The app's own library, once its window has set it up.
    static func library() async throws -> MacLibrary {
        let library = try #require(await until { MacLibrary.live }, "the app made no library")
        _ = await until { WindowOpener.shared.openReader }
        return library
    }

    /// `packages/test-fixtures/comics`, copied once into the container and scanned.
    ///
    /// The copy is the folder the library reads: the bundle sits inside the app, and a
    /// library folder inside the app it scans is a folder nobody would choose.
    static func fixtureLibrary() async throws -> MacLibrary {
        let library = try await library()
        let folder = URL.temporaryDirectory.appending(path: "walk-library", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            try FileManager.default.copyItem(at: TestFixtures.comics, to: folder)
        }
        if publication(named: "natural-sort", in: library) == nil {
            library.model.addFolder(folder)
        }
        _ = await until(.seconds(20)) {
            publication(named: "natural-sort", in: library) != nil
                && publication(named: "stored-entries", in: library) != nil ? true : nil
        }
        _ = await until(.seconds(20)) { () -> Bool? in
            if case .scanning = library.model.scanState { return nil }
            return true
        }
        await library.refreshProgress()
        return library
    }

    /// The publication whose file is `<name>.<ext>` in the fixture folder.
    static func publication(named name: String, in library: MacLibrary) -> Publication? {
        library.model.publications.first { publication in
            library.model.location(of: publication)?.deletingPathExtension().lastPathComponent == name
        }
    }

    /// Polls until `condition` answers, or the timeout passes.
    static func until<T>(_ timeout: Duration = .seconds(10), _ condition: () -> T?) async -> T? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if let value = condition() { return value }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    /// Lets the main loop turn a few times, for a step whose only sign is that nothing new appears.
    static func settle() async {
        try? await Task.sleep(for: .milliseconds(400))
    }

    /// The visible windows titled with this publication.
    static func readerWindows(for target: ReaderTarget) -> [NSWindow] {
        // The library window takes a publication's title while its page is shown, so it is
        // left out by identifier.
        NSApplication.shared.windows.filter { window in
            window.isVisible && window.title == target.title
                && !(window.identifier?.rawValue.hasPrefix(LibraryWindow.id) ?? false)
        }
    }

    /// Opens a reader the way a click on a cover does.
    static func open(_ target: ReaderTarget) throws {
        let open = try #require(WindowOpener.shared.openReader, "the library window has not set up its opener")
        open(target)
    }

    /// A key press, delivered to the window's first responder as the keyboard would.
    static func press(
        _ characters: String, keyCode: UInt16, in window: NSWindow, modifiers: NSEvent.ModifierFlags = []
    ) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            ) else { continue }
            window.sendEvent(event)
        }
    }

    /// Closes these windows and waits until they are gone.
    static func close(_ windows: [NSWindow]) async {
        for window in windows { window.performClose(nil) }
        _ = await until { windows.allSatisfy { !$0.isVisible } ? true : nil }
        // And until what they owed is written, so the next walk does not meet a late write.
        _ = await until { ProgressFlushers.shared.isIdle ? true : nil }
    }

    /// Where the container keeps frames: `~/Library/Containers/com.mecedric.storyarc/Data/tmp/captures/`.
    static func captureFolder(_ name: String) throws -> URL {
        let folder = URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory)
            .appending(path: "tmp/captures/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

enum KeyCode {
    static let rightArrow: UInt16 = 124
    static let leftArrow: UInt16 = 123
    static let space: UInt16 = 49
}
