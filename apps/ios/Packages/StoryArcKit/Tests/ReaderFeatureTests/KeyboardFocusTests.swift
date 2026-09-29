import Foundation
import Testing

/// The keyboard keys wait for focus that something now gives.
///
/// `.focusable()` alone offers to become the first responder; nothing takes the offer
/// up on its own, so `.onKeyPress` never fired on a device — a Mac's test host focuses
/// the one view in the window by default, which is why every other reader test in this
/// target passed regardless. `ReaderKeyboardFocus` binds a `@FocusState` with `.focused`
/// and sets it on appear, and again whenever a sheet that took focus away closes, which
/// is what a device needs.
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

    private func code(of name: String) throws -> String {
        let url = Self.readerFeature.appending(path: name)
        let text = try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has \(name) moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    @Test("The reader wraps its content in the keyboard-focus modifier")
    func wraps() throws {
        let view = try code(of: "ReaderView.swift")
        #expect(view.contains(".modifier(") && view.contains("ReaderKeyboardFocus("))
    }

    @Test("The modifier is bound to a focus state")
    func bound() throws {
        let modifier = try code(of: "ReaderKeyboardFocus.swift")
        #expect(modifier.contains("@FocusState private var isFocused: Bool"))
        #expect(modifier.contains(".focused($isFocused)"))
    }

    @Test("Focus is claimed on appear, and given back when the last sheet closes")
    func claimed() throws {
        let modifier = try code(of: "ReaderKeyboardFocus.swift")
        #expect(modifier.contains(".onAppear { isFocused = true }"))
        #expect(modifier.contains(".onChange(of: isCoveredBySheet)"))
    }

    @Test("Every sheet over the reader counts, the find and bookmarks sheet included")
    func everySheetCounts() throws {
        let view = try code(of: "ReaderView.swift")
        for sheet in ["isShowingMenu", "isBrowsingThumbnails", "isAdjusting", "isFindingText", "noting != nil"] {
            #expect(
                view.contains("|| \(sheet)") || view.contains("isCoveredBySheet: \(sheet)"),
                "\(sheet) no longer hands focus back when it closes."
            )
        }
    }
}
