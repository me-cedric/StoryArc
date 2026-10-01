import Foundation
import Testing

@testable import EpubReaderFeature

/// `native-experience`, *Opening the sheet*: on iPhone, a tap outside the theme sheet did
/// not dismiss it. `presentationBackgroundInteraction(.enabled(upThrough: .medium))` lets a
/// tap on the page reach `toggleChromeOrCloseTheme()` instead of the system dismissing the
/// popover, and that function only ever toggled the chrome — the sheet stayed open and the
/// tap that should have closed it disappeared into the page behind it. The Return key
/// shares the same function now, so this is also what it closes.
@Suite("A tap on the page closes the theme sheet, not the chrome behind it")
struct ThemeSheetTapOutsideTests {

    private static let root: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { directory.deleteLastPathComponent() }
        return directory
    }()

    private func viewSource() throws -> String {
        let url = Self.root.appendingPathComponent(
            "apps/ios/Packages/StoryArcEpub/Sources/EpubReaderFeature/EpubReaderView.swift"
        )
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    @Test("While the theme sheet is up, the page tap closes it rather than toggling the chrome")
    func thePageTapClosesTheSheetFirst() throws {
        let source = try viewSource()

        let function = try #require(
            source.range(of: "private func toggleChromeOrCloseTheme() {")
        )
        let functionBody = String(source[function.upperBound...].prefix(300))

        #expect(
            functionBody.contains("if isShowingTheme {") && functionBody.contains("isShowingTheme = false"),
            """
            The tap-and-Return function no longer checks `isShowingTheme` first. Before this, \
            a tap on the page while the theme sheet was up only ever toggled `isChromeVisible`, \
            so the sheet had no way to close from a tap outside it.
            """
        )
    }

    @Test("Closing the sheet from a page tap does not also toggle the chrome in the same tap")
    func theSheetCloseDoesNotAlsoToggleChrome() throws {
        let source = try viewSource()

        let function = try #require(
            source.range(of: "private func toggleChromeOrCloseTheme() {")
        )
        let functionBody = String(source[function.upperBound...].prefix(300))

        #expect(
            functionBody.contains("isShowingTheme = false\n        } else {"),
            """
            The chrome toggle must sit in the `else` branch, so a tap that closes the sheet \
            does not also flip `isChromeVisible` in the same gesture.
            """
        )
    }
}
