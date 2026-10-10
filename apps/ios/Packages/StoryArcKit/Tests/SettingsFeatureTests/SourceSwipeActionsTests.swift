import Foundation
import Testing

/// Task 27.3 of `close-the-audited-gaps` (decision O29): on a "Your libraries" row, Remove is the
/// last swipe action, alone at the screen edge, in the danger colour, and it asks first.
///
/// A host test cannot draw a swipe action, so this reads the source. It is a tripwire: the
/// device frames in `docs/designs/screenshots/polish-ios-2026-10-10` are the proof.
@Suite("Your libraries swipe actions")
struct SourceSwipeActionsTests {
    private static let view: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<2 { directory.deleteLastPathComponent() }
        return directory.appendingPathComponent("../Sources/SettingsFeature/SourcesSettings.swift").standardized
    }()

    @Test("Remove is first in the trailing builder, red, and only sets the item to confirm")
    func removeIsLastRedAndConfirmed() throws {
        let text = try String(contentsOf: Self.view, encoding: .utf8)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let builder = try #require(text.range(of: "private func actions(for source: Source)"))
        let body = String(text[builder.upperBound...])
        let remove = try #require(body.range(of: "Button(role: .destructive) { removing = source }"))
        let rename = try #require(body.range(of: "renaming = source"))
        let tint = try #require(body.range(of: ".tint(StoryArcColor.Status.danger)"))

        #expect(remove.lowerBound < rename.lowerBound, "Remove is not the action at the screen edge.")
        #expect(tint.lowerBound < rename.lowerBound, "Remove is not drawn in the danger colour.")
        #expect(text.contains(".swipeActions(edge: .trailing) { actions(for: source) }"))
        #expect(text.contains(".confirmationDialog("), "Remove does not ask before it acts.")
    }
}
