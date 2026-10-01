import Foundation
import Testing

/// `page-transitions`: "one key — Return — toggles the chrome", the same way a centre tap
/// does. No key did before this; the arrow, page and space keys turned pages and nothing
/// brought the chrome back once a reader had hidden it from a keyboard.
///
/// Source text, the way `TapZoneWiringTests` is: the claim is that the key is bound at
/// all, which a unit test of `toggleChrome()` alone cannot show — it would pass just as
/// well with the `.onKeyPress` line deleted.
@Suite("The Return key toggles the comic reader's chrome")
struct ReturnKeyTogglesChromeTests {
    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory
    }()

    private func source(_ relativePath: String) throws -> String {
        let url = Self.appleRoot.appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    @Test("Return is bound beside the other turn keys")
    func returnIsBound() throws {
        let view = try source("Packages/StoryArcKit/Sources/ReaderFeature/ReaderView.swift")
        #expect(view.contains(".onKeyPress(.return) { toggleChrome(); return .handled }"))
    }

    @Test("toggleChrome is what a centre tap already calls")
    func sharesTheTapsFunction() throws {
        let turning = try source("Packages/StoryArcKit/Sources/ReaderFeature/ReaderTurning.swift")
        #expect(turning.contains("func toggleChrome() {"))
        #expect(turning.contains("} else {\n            toggleChrome()\n        }"))
    }
}
