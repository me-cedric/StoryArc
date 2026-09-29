import Foundation
import Testing

/// The comic reader's transition menu names the reason on every unavailable row, not only
/// the chosen one.
///
/// `page-transitions` "A mode is unavailable for the content": "shown unavailable with a
/// one-line reason, never silently absent". Before this, the reason showed once, under the
/// closed menu's own label, for `choices.chosen` alone — a reader browsing Curl, Slide and
/// Fast fade inside the open menu saw two disabled rows with no reason on either. Android's
/// `TransitionRow` already draws the reason as a second line inside each `DropdownMenuItem`;
/// this is that row, in `Menu` terms.
///
/// **A second, bare `Text` in a `Menu` button's label is what SwiftUI reads as that row's
/// subtitle** — not a `Label`, which reserves its second slot for an icon, and not a
/// `VStack`, which a native menu flattens back to one line. This reads source text, the
/// trade `ReaderMenuOnGlassTests` and `TapZoneWiringTests` make for the same reason: `Menu`
/// composes into a live `UIMenu`, which a host-run `swift test` cannot open to read a pixel
/// from.
@Suite("The transition menu names a reason on every unavailable row")
struct TransitionRowSubtitleTests {

    /// The package directory, from this test's own compiled path. See
    /// `ReaderMenuOnGlassTests` for why this is `#filePath` and not a walk from the
    /// working directory.
    private static let package: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func transitionRow() throws -> String {
        let url = Self.package.appending(path: "Sources/ReaderFeature/ReaderMenuSettings.swift")
        let text = try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
        let opening = try #require(
            text.range(of: "private var transitionRow: some View {"),
            "ReaderMenuSettings.swift no longer declares `transitionRow` — has it moved?"
        )
        let rest = text[opening.upperBound...]
        let closing = try #require(
            rest.range(of: "\n    }"),
            "`transitionRow` is not closed where this guard expects it."
        )
        return String(rest[..<closing.lowerBound])
    }

    @Test("Each row's label carries a second, bare Text for its reason")
    func rowCarriesASubtitle() throws {
        let row = try transitionRow()
        #expect(
            row.contains("if let reason = choices.unavailable[mode] {"),
            "The transition row no longer reads a reason per offered mode."
        )
        // Bare, not wrapped: `Text(reason.titleKey, bundle: .module)` on its own line inside
        // the button's label, a sibling of the title rather than nested inside it — nesting
        // it in the `Label` or in a container is what a native `Menu` flattens away.
        #expect(
            row.contains("Text(reason.titleKey, bundle: .module)\n                    }"),
            """
            The reason is no longer a bare sibling `Text` in the row's label. Wrapped in a \
            `Label` or a container, a native `Menu` draws one line and the reason is silently \
            dropped.
            """
        )
    }

    @Test("The reason is still read from the same table every other reader uses")
    func reasonComesFromTransitionChoices() throws {
        let row = try transitionRow()
        #expect(row.contains("choices.unavailable[mode]"))
    }
}
