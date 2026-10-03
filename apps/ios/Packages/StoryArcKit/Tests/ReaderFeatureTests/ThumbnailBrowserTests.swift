import Foundation
import Testing

@testable import ReaderFeature

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

        // The carousel's own row, not the whole menu: the menu jumps from other rows too.
        let menu = try code(of: "ReaderMenu.swift")
        let row = menu.components(separatedBy: "var thumbnailBrowserRow").dropFirst().first?
            .components(separatedBy: "\n    func ").first ?? ""
        #expect(
            row.contains("ThumbnailStrip(") && row.contains("jump(to: index)"),
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

    @Test("The centred page sits in the middle of the carousel")
    func centredPageSitsInTheMiddle() {
        let viewport: CGFloat = 393
        let margin = ThumbnailStrip.contentMargin(viewportWidth: viewport)
        #expect(abs(margin * 2 + ThumbnailStrip.centredCellWidth - viewport) < 0.001)
    }

    @Test("The carousel closes with the menu it is a row of")
    func carouselClosesWithTheMenu() throws {
        let menu = try code(of: "ReaderMenu.swift")
        #expect(
            menu.contains(".onDisappear { isBrowsingThumbnails = false }"),
            """
            The carousel stays open after the menu closes. The chrome timer and the keyboard \
            focus both read `isBrowsingThumbnails` as a surface over the page, so the chrome \
            never hides and the page never takes focus back.
            """
        )
    }

    @Test("A page turned while the carousel is open becomes its centred page")
    func carouselFollowsTheCurrentPage() throws {
        let strip = try code(of: "ThumbnailStrip.swift")
        #expect(
            strip.contains(".onChange(of: currentIndex) { _, new in centredIndex = new }"),
            """
            The carousel no longer follows the page the reader is on. A page turned behind the \
            half-height menu, or a VoiceOver step on the slider, leaves the preview behind.
            """
        )
    }

    @Test("Each cell is announced as its page and its chapter")
    func cellsAnnounceTheirChapter() throws {
        let strip = try code(of: "ThumbnailStrip.swift")
        #expect(
            strip.contains("chapterName: chapterName") && strip.contains("Text(\"\\(page), \\(chapterName)\")"),
            """
            A cell no longer announces its chapter. `page-browser-carousel`: VoiceOver \
            "announces the page number and, when the publication has chapter markers, the \
            chapter name".
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

    /// PB-open: opening the carousel assigns `true`; it does not toggle.
    ///
    /// The Contents row now calls `openContents()` from two recognizers — the `Button`'s
    /// own action and a `simultaneousGesture`, added because the row sits first in the
    /// sheet's `List`, directly under the grabber `.presentationDetents` uses to drag the
    /// sheet between its two heights, and without a competing recognizer that drag
    /// sometimes won the arena and swallowed the tap (`SweepComicReaderTests
    /// .testCaptureComicPageBrowser` failed "Contents opened no page browser" on every run,
    /// on a booted simulator). A tap both recognizers accept calls this method twice.
    /// `.toggle()` would make that net back to `false`; an assignment is idempotent.
    @Test("Opening the carousel is idempotent, not a toggle")
    func openingTheCarouselIsIdempotent() throws {
        let progress = try code(of: "ReaderMenuProgress.swift")
        #expect(
            progress.contains(".simultaneousGesture(TapGesture().onEnded { openContents() })"),
            """
            The Contents row lost its simultaneous tap. PB-open: without it, the sheet's \
            drag under the grabber can take the tap, and the carousel never opens.
            """
        )
        #expect(
            progress.contains("isBrowsingThumbnails = true"),
            """
            The Contents row no longer assigns `isBrowsingThumbnails = true` to open the \
            carousel. PB-open: a toggle is not idempotent, and a tap this reader (or a UI \
            test) delivers twice for one touch must still leave the carousel open.
            """
        )
        #expect(
            !progress.contains("isBrowsingThumbnails.toggle()"),
            """
            The Contents row toggles `isBrowsingThumbnails` again. PB-open: two toggles for \
            one tap net back to `false`, and the carousel the tap asked for never appears.
            """
        )
    }
}
