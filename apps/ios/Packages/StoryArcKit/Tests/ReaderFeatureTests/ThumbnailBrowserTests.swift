import Foundation
import Testing

/// That the thumbnail browser shows the whole publication, says where the reader is, and
/// goes where it is told.
///
/// `comic-reader`, *Thumbnail browser*:
///
/// > **THEN** every page is shown in a scrollable strip with the current page marked, and
/// > tapping one jumps to it
///
/// Three claims, one per test below. The middle one carries a fourth that `native-experience`
/// adds and this strip honours: the mark is not colour alone, because a border is only
/// colour.
///
/// **Why it reads the source text, which is the second-best test.** The honest test scrolls
/// the strip on a booted simulator and taps a cell. `pnpm test:ios` runs `swift test` on the
/// host, where there is no strip to scroll, and no gate in this repository boots a simulator.
/// `ReaderMenuTests` is the same choice made for the same reason and carries the same
/// warning: this is a tripwire, not a proof. It says the strip is built over every page; it
/// never says a thumbnail appeared.
@Suite("The thumbnail browser shows every page and goes where it is told")
struct ThumbnailBrowserTests {

    /// The package directory, from this test's own compiled path. See `ReaderChromeTests`
    /// for why this is `#filePath` and not a walk up from the working directory.
    private static let package: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func source(_ name: String) -> URL {
        package.appending(path: "Sources/ReaderFeature/\(name)")
    }

    /// A file's code, with its prose removed.
    ///
    /// Comments are stripped first: this codebase explains itself at length, and a guard that
    /// found `isCurrent` in a paragraph about the current page would be measuring the
    /// documentation.
    private func code(of name: String) throws -> String {
        let url = Self.source(name)
        let text = try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has the thumbnail browser moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    @Test("The strip is built over every page of the publication")
    func everyPageIsInTheStrip() throws {
        let strip = try code(of: "ThumbnailStrip.swift")
        #expect(
            strip.contains("ForEach(model.pages.indices"),
            """
            The thumbnail strip is no longer built over `model.pages.indices`. \
            `comic-reader` requires "every page ... shown in a scrollable strip", and a strip \
            built over a window of the pages shows the reader a publication shorter than the \
            one they are holding.
            """
        )
    }

    /// Marked, and not by colour alone.
    ///
    /// `native-experience` forbids colour as the only signal, and a highlighted border is
    /// only colour. The page number carries the mark as weight as well.
    @Test("The page being read is marked, and not by colour alone")
    func theCurrentPageIsMarked() throws {
        let strip = try code(of: "ThumbnailStrip.swift")
        #expect(
            strip.contains("isCurrent: index == currentIndex"),
            """
            The thumbnail strip no longer marks the current page. `comic-reader` requires the \
            strip to be shown "with the current page marked" — without it a reader forty \
            pages in is handed three hundred identical cells.
            """
        )
        #expect(
            strip.contains("fontWeight(isCurrent ?"),
            """
            The current page is marked by colour alone. `native-experience` forbids colour as \
            the only signal, and the highlighted border is only colour. The page number's \
            weight is what carries the mark for a reader who cannot tell the two borders \
            apart.
            """
        )
        #expect(
            strip.contains("accessibilityAddTraits(isCurrent ? [.isButton, .isSelected]"),
            """
            The current page is not announced as selected. A mark drawn and not spoken is no \
            mark at all to a reader using VoiceOver, and `comic-reader` asks for the page to \
            be marked rather than for it to be coloured.
            """
        )
    }

    @Test("Tapping a thumbnail jumps to that page")
    func tappingJumps() throws {
        let strip = try code(of: "ThumbnailStrip.swift")
        #expect(
            strip.contains("onTapGesture { onSelect(index) }"),
            """
            A thumbnail no longer reports the page it stands for. `comic-reader`: "tapping \
            one jumps to it".
            """
        )

        let menu = try code(of: "ReaderMenu.swift")
        #expect(
            menu.contains("ThumbnailStrip(") && menu.contains("jump(to: index)"),
            """
            The menu no longer turns a tapped thumbnail into a jump. `comic-reader`: "tapping \
            one jumps to it" — and a jump rather than a turn, so the way back from a mis-tap \
            in a three-hundred-page strip is the one control `PageReturn` already offers.
            """
        )
    }

    @Test("The carousel mirrors for a right-to-left publication")
    func carouselMirrorsForRightToLeft() throws {
        let strip = try code(of: "ThumbnailStrip.swift")
        #expect(
            strip.contains("sliderLayoutDirection(isRightToLeft:"),
            """
            The carousel no longer mirrors its scroll content for a right-to-left \
            publication. `page-browser-carousel`: "the carousel runs right to left, with \
            page one at the right end, the same way as the mirrored page slider".
            """
        )
    }

    @Test("A drag on the slider centres the carousel, with no animation")
    func sliderDragCentresTheCarousel() throws {
        let slider = try code(of: "ReaderSlider.swift")
        #expect(
            slider.contains("centredPreviewIndex = index"),
            """
            A slider drag no longer sets the carousel's centred page. \
            `page-browser-carousel` §3: "the slider's value sets the carousel's centred \
            page with no animation".
            """
        )
    }
}
