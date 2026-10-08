import Foundation
import Testing

/// The bar's title and chapter caption are drawn in the glass text styles.
///
/// `close-the-audited-gaps` 23.7: the accessibility audit reported "Contrast failed" on the
/// bar's text. The bar is the system's glass over a page that scrolls beneath it, so no palette
/// colour is right for every backdrop; the hierarchical styles resolve against the material,
/// which is what `storyArcGlassText` states. A view cannot be composed on the host, so this
/// reads the source, as ``PlayerDockFocusTests`` does and for the same reason. It proves the
/// styles are declared and never what the audit measures; `PlayerAuditTests` on a simulator is
/// that.
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

    @Test("The title takes the primary glass style and the chapter the secondary one")
    func titleAndChapterUseGlassText() {
        let text = Self.source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(text.contains("Text(bar.label.title) .textRole(.subheadline) .storyArcGlassText(.primary)"))
        #expect(text.contains("Text(chapter) .textRole(.caption) .storyArcGlassText(.secondary)"))
    }
}
