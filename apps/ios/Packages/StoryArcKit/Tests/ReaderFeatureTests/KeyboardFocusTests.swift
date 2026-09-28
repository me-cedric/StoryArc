import Foundation
import Testing

/// The keyboard keys wait for focus that something now gives.
///
/// `.focusable()` alone offers to become the first responder; nothing takes the offer
/// up on its own, so `.onKeyPress` never fired on a device — a Mac's test host focuses
/// the one view in the window by default, which is why every other reader test in this
/// target passed regardless. `@FocusState` bound with `.focused` and set on appear, and
/// again whenever a sheet that took focus away closes, is what a device needs.
///
/// **Why it reads the source text**, the way `ReaderGestureTests` does for the same
/// reason: focus is a property of a live window, which this host-run suite has no way
/// to open. This is a tripwire, not a proof — it says the binding is there, never that
/// a key was pressed on a device.
@Suite("Keyboard focus")
struct KeyboardFocusTests {

    private static let readerFeature: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/ReaderFeature")

    private var code: String {
        get throws {
            let url = Self.readerFeature.appending(path: "ReaderView.swift")
            let text = try #require(
                try? String(contentsOf: url, encoding: .utf8),
                "\(url.path) could not be read — has ReaderView.swift moved?"
            )
            return text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    guard let comment = line.range(of: "//") else { return String(line) }
                    return String(line[line.startIndex..<comment.lowerBound])
                }
                .joined(separator: "\n")
        }
    }

    @Test("The keyboard-driven view is bound to a focus state")
    func bound() throws {
        #expect(try code.contains("@FocusState var isKeyboardFocused: Bool"))
        #expect(try code.contains(".focused($isKeyboardFocused)"))
    }

    @Test("Focus is claimed on appear, and given back when a sheet closes")
    func claimed() throws {
        let source = try code
        #expect(source.contains(".onAppear { isKeyboardFocused = true }"))
        #expect(source.contains("isShowingMenu"))
        #expect(source.contains("isBrowsingThumbnails"))
        #expect(source.contains("isAdjusting"))
    }
}
