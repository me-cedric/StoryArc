import Foundation
import Testing

/// The bar's title and chapter caption are drawn in the palette's text colours.
///
/// `close-the-audited-gaps` 23.7 gave them the hierarchical glass styles, and 27.6 took them
/// back: in the light appearance that style resolved to white on glass that is pale there
/// (2.0 to 1 in catalogue entry 08), because the bottom accessory hands its content the tab
/// bar's own adaptive scheme and not the app's. The palette colours follow the app's
/// appearance, like the glass and the two buttons beside the text. A view cannot be composed on
/// the host, so this reads the source, as ``PlayerDockFocusTests`` does and for the same
/// reason. It proves the colours are declared and never what the eye measures:
/// `DetailAndPlayerCatalogueTests.testTheDockTitleReadsOnItsGlassInBothAppearances` draws the
/// bar and measures the title, and is the real proof.
@Suite("The dock's text styles")
struct PlayerDockGlassTextTests {
    private static let source: String = {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        let path = directory.appending(path: "Sources/PlayerFeature/PlayerDock.swift").path
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            fatalError("\(path) is not readable. Has PlayerDock.swift moved?")
        }
        return text
    }()

    @Test("The title takes the primary palette colour and the chapter the secondary one")
    func titleAndChapterUsePaletteText() {
        let text = Self.source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let title = "Text(bar.label.title) .textRole(.subheadline) .foregroundStyle(theme.palette.textPrimary)"
        let chapter = "Text(chapter) .textRole(.caption) .foregroundStyle(theme.palette.textSecondary)"
        #expect(text.contains(title))
        #expect(text.contains(chapter))
    }
}
