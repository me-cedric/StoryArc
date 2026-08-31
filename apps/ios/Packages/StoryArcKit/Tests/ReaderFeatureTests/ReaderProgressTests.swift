import Foundation
import Testing

/// That progress is sized to the format: a slider where pages are the unit, words where they
/// are not, and a fill that says nothing twice.
///
/// `ebook-reader`, *Progress display*:
///
/// > **AND** no slider is offered, and the position is not drawn over the page
///
/// `comic-reader`, *Page slider with thumbnails* and *Where the reader is, at a glance*:
///
/// > **WHEN** a user opens the reader's menu on a publication with fixed pages and drags the
/// > page slider **THEN** a thumbnail of the target page follows the drag …
/// > **AND** releasing jumps there and dismisses the menu, with a control to return to the
/// > previous position
/// > …
/// > **AND** the text is what conveys the position, so the fill may be absent without
/// > anything being lost — it is not the only indication
///
/// ``ReadingPositionLineTests`` owns what the line *says*, and it is a real unit test over a
/// pure type. This suite owns where the line and the slider are *drawn*, which no host test
/// can measure — so it reads the source, and it is a tripwire rather than a proof. It says the
/// reflowable reader declares no slider; it never says a slider failed to appear.
///
/// The absence is the assertion worth having. `ebook-reader`'s reasoning is that a slider
/// whose track is measured in reflowable pages is the same claim as a reflowable page number,
/// which the app refuses to present — and an absence is not something a compiler notices
/// returning.
@Suite("Progress sized to the format")
struct ReaderProgressTests {

    /// The package directory, from this test's own compiled path. See `ReaderChromeTests` for
    /// why this is `#filePath` and not a walk up from the working directory.
    private static let package: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Every file the reflowable reader's progress and menu are drawn from.
    private static var reflowable: [URL] {
        let tree = package
            .deletingLastPathComponent()
            .appending(path: "StoryArcEpub/Sources/EpubReaderFeature")
        return ["EpubReaderChrome.swift", "EpubReaderMenu.swift", "EpubReaderProgress.swift"]
            .map { tree.appending(path: $0) }
    }

    /// The comic reader's, likewise.
    private static var comic: [URL] {
        let tree = package.appending(path: "Sources/ReaderFeature")
        return ["ReaderChrome.swift", "ReaderMenu.swift", "ReaderMenuProgress.swift",
                "ReaderMenuSettings.swift", "ReaderSlider.swift"]
            .map { tree.appending(path: $0) }
    }

    private func code(_ urls: [URL]) throws -> String {
        var joined = ""
        for url in urls {
            let text = try #require(
                try? String(contentsOf: url, encoding: .utf8),
                "\(url.path) could not be read — has it moved?"
            )
            joined += text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    guard let comment = line.range(of: "//") else { return String(line) }
                    return String(line[line.startIndex..<comment.lowerBound])
                }
                .joined(separator: "\n")
            joined += "\n"
        }
        return joined
    }

    @Test("A reflowable publication offers no slider, anywhere in its reader")
    func noSliderForAReflowablePublication() throws {
        let code = try code(Self.reflowable)

        #expect(
            !code.contains("Slider("),
            """
            The reflowable reader declares a `Slider`. `ebook-reader` forbids it: "pages are \
            not the unit a novel is read in, and the app already refuses to treat a \
            reflowable page number as a stable identity — a slider whose track is measured in \
            those pages is that same claim in another form". The table of contents is how a \
            reader goes somewhere else, and it is on the same menu.
            """
        )
    }

    @Test("A fixed-page publication keeps its slider, its thumbnail, and the way back")
    func theSliderSurvivesForAComic() throws {
        let code = try code(Self.comic)

        let kept: [(what: String, spelling: String)] = [
            ("the slider itself", "Slider("),
            ("the thumbnail that follows the drag", "ScrubThumbnail("),
            ("the scrub that moves nothing until released", "if let target = scrubbing"),
            ("the menu leaving on release", "isShowingMenu = false"),
            ("the way back from the jump", "returnFromJump()"),
        ]

        for item in kept {
            #expect(
                code.contains(item.spelling),
                """
                The comic reader has lost \(item.what) — `\(item.spelling)` is not in its \
                menu. `comic-reader` keeps the slider "in the reader's menu rather than over \
                the page", with the thumbnail follow intact, and requires that "releasing \
                jumps there and dismisses the menu, with a control to return to the previous \
                position".
                """
            )
        }
    }

    @Test("The coarse fill is decorative on both readers, and the text carries the meaning")
    func theFillSaysNothingTwice() throws {
        for reader in [(name: "The comic reader", files: Self.comic),
                       (name: "The reflowable reader", files: Self.reflowable)] {
            let code = try code(reader.files)

            #expect(
                code.contains("Rectangle()"),
                """
                \(reader.name) draws no coarse fill. `comic-reader` asks for the position to \
                be "drawn as a fill behind the menu's own contents row", as a `Rectangle` in \
                a `GeometryReader` on this platform.
                """
            )
            #expect(
                code.contains(".accessibilityHidden(true)"),
                """
                \(reader.name)'s coarse fill is not hidden from assistive technology. \
                `comic-reader`: "the text is what conveys the position, so the fill may be \
                absent without anything being lost — it is not the only indication". A \
                percentage announced twice is a percentage announced wrong.
                """
            )
        }
    }
}
