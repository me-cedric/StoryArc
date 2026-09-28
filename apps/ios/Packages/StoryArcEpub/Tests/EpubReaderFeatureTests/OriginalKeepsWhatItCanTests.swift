import Foundation
import Testing

/// `reading-themes`, *Original*, and `ebook-reader`'s publisher-styles scenario: under
/// Original, every axis Readium cannot honour draws as unavailable, in the notice — and
/// every axis it can honour stays a live control, margins included.
///
/// A source tripwire, for the reason `ThemeAxisResetTests` gives at length: no JVM or XCTest
/// host lays out this sheet, so these cases say the wiring is written and never that a
/// finger reached it. What `ReadiumMapping` sends to Readium under Original is proved over
/// `preferences(values:)` in `ReadiumMappingTests`.
@Suite("Original keeps what it can, and only that")
struct OriginalKeepsWhatItCanTests {

    @Test("Margins draws outside the branch publisher styles hides")
    func marginsIsAlwaysDrawn() throws {
        let sheet = try Self.source("ThemeAxesSheet.swift")

        let margins = try #require(
            sheet.range(of: "marginsControl"),
            """
            The sheet no longer draws `marginsControl` at all, so margins is gone under \
            every preset, Original included.
            """
        )
        let branch = try #require(
            sheet.range(of: "if model.theme.preset.keepsPublisherStyles"),
            """
            The sheet no longer branches on `keepsPublisherStyles`, so this test cannot \
            say which side of it margins is on.
            """
        )

        #expect(
            margins.lowerBound < branch.lowerBound,
            """
            `marginsControl` moved inside the `keepsPublisherStyles` branch, so margins is \
            hidden under Original again. `ThemeAxis.requiresPublisherStylesOff` says \
            margins reaches the page under every preset, the same as font size, family \
            and weight.
            """
        )
    }

    @Test("Hyphenation is not a live control under Original")
    func hyphenationIsNotInTypeface() throws {
        let sheet = try Self.source("ThemeAxesSheet.swift")

        guard let typefaceStart = sheet.range(of: "var typeface: some View") else {
            Issue.record("`typeface` no longer exists in ThemeAxesSheet.swift.")
            return
        }
        let afterTypeface = sheet[typefaceStart.lowerBound...]
        let nextProperty = afterTypeface.range(
            of: "\n    private var hyphenationToggle",
        ) ?? afterTypeface.range(of: "\n    private var alignment")
        let typefaceBody = nextProperty.map { String(afterTypeface[..<$0.lowerBound]) }
            ?? String(afterTypeface)

        #expect(
            !typefaceBody.contains("hyphenationBinding"),
            """
            `typeface` still toggles hyphenation, and `typeface` draws under every preset \
            including Original, where a publisher's own stylesheet can set `hyphens` — \
            `ThemeAxis.requiresPublisherStylesOff` puts hyphenation with the axes publisher \
            styles overrides. A live toggle that changes nothing on the page is the defect \
            `reading-themes`'s publisher-styles scenario forbids.
            """
        )
    }

    @Test("Hyphenation moves into the branch that only draws off Original")
    func hyphenationIsOnlyOffOriginal() throws {
        let sheet = try Self.source("ThemeAxesSheet.swift")

        let toggle = try #require(
            sheet.range(of: "hyphenationToggle"),
            """
            The sheet no longer draws `hyphenationToggle` anywhere, so the reader has no \
            way left to turn hyphenation on or off.
            """
        )
        let elseBranch = try #require(
            sheet.range(of: "} else {"),
            """
            The sheet's preset branch no longer has an else, so this test cannot say \
            which side of it hyphenation is on.
            """
        )

        #expect(
            toggle.lowerBound > elseBranch.lowerBound,
            """
            `hyphenationToggle` draws outside the branch that only runs when publisher \
            styles are off, so it would still show as a live control under Original.
            """
        )
    }

    @Test("The notice still names hyphenation as unavailable under Original")
    func noticeStillNamesHyphenation() throws {
        let sheet = try Self.source("ThemeAxesSheet.swift")

        #expect(
            sheet.contains("ThemeAxis.allCases.filter(\\.requiresPublisherStylesOff)"),
            """
            The publisher-styles notice no longer lists every axis `requiresPublisherStylesOff` \
            names, which is where hyphenation now has to be named instead of a live control.
            """
        )
    }

    private static let package: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func source(_ name: String) throws -> String {
        try String(contentsOf: package.appending(path: "Sources/EpubReaderFeature/\(name)"),
                   encoding: .utf8)
    }
}
