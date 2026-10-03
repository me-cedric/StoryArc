import Foundation
import Testing

/// Every reader glass button falls back to the app's own opaque pair under Reduce
/// Transparency or Increase Contrast — task 9.8.
///
/// `GlassChrome` (`DesignSystem/Glass.swift`) already made this promise for a
/// *container*: "every translucent chrome surface is replaced by its declared opaque
/// fill" with "borders strengthened". The reader's five buttons never took it, because
/// `.buttonStyle(.glass)` is the system's own adaptive style, and the system's own
/// fallback is not this app's two tokens — so a reader who turned on either setting saw
/// every other glass surface in the app answer with `surfaceOverlay`/`borderStrong` and
/// the reader's own buttons answer with something else.
///
/// **This reads source text, the same trade `GlassIsUntintedTests` and
/// `ReaderChromeTests` make and explain.** Composing these views and reading Reduce
/// Transparency needs a simulator; `pnpm test:ios` runs `swift test` on the host. It
/// cannot see a rendered pixel; it can see which modifier a button declares, which is
/// the thing that regressed.
@Suite("Every reader glass button falls back the app's own way")
struct ReaderGlassButtonFallbackTests {

    /// The three packages this repository's reader chrome is spread across, from this
    /// test's own compiled path — not a walk up from the working directory, which a
    /// worktree checkout would leave climbing into the parent's copy.
    private static let kit: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ReaderFeatureTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // StoryArcKit

    private static var glassSource: URL {
        kit.appending(path: "Sources/DesignSystem/Glass.swift")
    }

    private static var readerChrome: URL {
        kit.appending(path: "Sources/ReaderFeature/ReaderChrome.swift")
    }

    private static var readerSlider: URL {
        kit.appending(path: "Sources/ReaderFeature/ReaderSlider.swift")
    }

    private static var epubReaderChrome: URL {
        kit.deletingLastPathComponent().appending(path: "StoryArcEpub/Sources/EpubReaderFeature/EpubReaderChrome.swift")
    }

    private func read(_ url: URL) throws -> String {
        try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    /// How many times `needle` appears, as a whole line once trimmed — the same
    /// precision `GlassIsUntintedTests` needs for the same reason: a modifier that is
    /// commented out, or named in a doc comment, is not a call site.
    private func lineCount(of needle: String, in text: String) -> Int {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix(needle) }
            .count
    }

    @Test(
        "Each reader glass button takes the fallback helper, not the bare system style",
        arguments: [
            (readerChrome, "The comic reader's chrome", 2),
            (epubReaderChrome, "The reflowable reader's chrome", 2),
            (readerSlider, "The return-from-jump control", 1),
        ]
    )
    func takesTheHelper(file: URL, reader: String, expectedSites: Int) throws {
        let source = try read(file)

        #expect(
            lineCount(of: ".buttonStyle(.glass)", in: source) == 0,
            "\(reader) still calls the bare system style, which has no app-declared fallback."
        )
        let actualSites = lineCount(of: ".storyArcGlassButton(", in: source)
        #expect(
            actualSites == expectedSites,
            "\(reader) declares \(actualSites) glass button(s) through the helper, not \(expectedSites)."
        )
    }

    @Test("The helper's fallback is the app's own surfaceOverlay/borderStrong pair, under both settings")
    func helperFallsBackToTheAppsOwnTokens() throws {
        let source = try read(Self.glassSource)

        guard let range = source.range(of: "private struct GlassButtonChrome") else {
            Issue.record("GlassButtonChrome has moved or been renamed in Glass.swift.")
            return
        }
        let body = String(source[range.lowerBound...])

        #expect(
            body.contains("reduceTransparency || contrast == .increased"),
            "The fallback must fire for Increase Contrast too — `native-experience` names both in one breath."
        )
        #expect(body.contains(".background(palette.surfaceOverlay"), "The fallback must be surfaceOverlay.")
        #expect(body.contains("palette.borderStrong"), "The fallback must strengthen the border.")
        // The size itself is measured in `OpaqueChromeButtonStyleTests`. This line checks
        // that the measured frame is also the area a tap hits.
        #expect(body.contains(".contentShape(shape)"), "The 44 pt frame must be the tap target too.")
    }
}
