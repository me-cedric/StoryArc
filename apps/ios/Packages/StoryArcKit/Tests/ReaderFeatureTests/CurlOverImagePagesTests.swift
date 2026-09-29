import Foundation
import Testing

/// That a curl over a comic page turns the page that was already decoded.
///
/// `comic-reader`, *Curl over image pages*:
///
/// > **WHEN** a curl runs over a comic page
/// > **THEN** it uses the already-decoded page directly rather than a re-raster, because the
/// > page is an image before the turn begins
///
/// **Two claims, and this suite asserts both.** The curl is handed what the decoder produced
/// — `ReaderModel.image(at:)`, a `CGImage` — for all three sheets it can draw. And nothing on
/// the curl's path turns a view back into a picture, which is the cost the scenario exists to
/// forbid: a snapshot at the start of every turn is a full-page render on the frame a finger
/// is already moving.
///
/// The second claim is the one a compiler cannot make. Handing `CurledPages` a snapshot is
/// legal Swift — `ImageRenderer` produces a `CGImage` like any other — so a container that
/// re-rendered the page would pass every other gate in this repository.
///
/// **Why it reads the source text, which is the second-best test.** The honest test measures
/// the frame a turn costs on a device, and `FrameProbe` is that instrument; no gate in this
/// repository runs it. `ReaderChromeTests` and `TapZoneWiringTests` are the same choice made
/// for the same reason and carry the same warning: this is a tripwire, not a proof.
@Suite("A curl turns the decoded page, not a picture of it")
struct CurlOverImagePagesTests {

    /// The package directory, from this test's own compiled path. See `ReaderChromeTests`
    /// for why this is `#filePath` and not a walk up from the working directory.
    private static let package: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The container that builds the curl, and the curl itself.
    private static var curlPath: [(name: String, url: URL)] {
        ["ReaderContainers.swift", "CurledPages.swift"].map {
            ($0, package.appending(path: "Sources/ReaderFeature/\($0)"))
        }
    }

    /// A file's code, with its prose removed.
    ///
    /// Comments are stripped first: this codebase explains itself at length, and both
    /// "re-raster" and `ImageRenderer` are words it uses in its own paragraphs about them.
    private func code(of url: URL) throws -> String {
        let text = try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has the curl moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// Each sheet the curl can draw, in the order the container hands them over.
    private static let sheets = ["page:", "beneath:", "previous:"]

    /// Just one brace-delimited body, found by its opening line.
    ///
    /// The file holds several bodies, and each of the other containers reads a decoded
    /// page too. Counting over the whole file would pass while one of these read none.
    private func body(opening line: String, in container: String, missing: Comment) throws -> String {
        let opening = try #require(container.range(of: line), missing)
        let rest = container[opening.upperBound...]
        let closing = try #require(
            rest.range(of: "\n    }"),
            "`\(line)` is not closed where this guard expects it."
        )
        return String(rest[..<closing.lowerBound])
    }

    private func curlBuilder() throws -> String {
        try body(
            opening: "var curled: some View {",
            in: try code(of: Self.curlPath[0].url),
            missing: "`ReaderContainers.swift` no longer declares `var curled` — has the curl moved?"
        )
    }

    /// The function each sheet is decoded and adjusted through. `comic-reader`
    /// "Persisting adjustments" (task 8.1) is what put this between the curl and
    /// `model.image(at:)`: the trim and the sharpening apply to a curled page exactly as
    /// they apply to every other container's.
    private func adjustedImageBuilder() throws -> String {
        try body(
            opening: "private func adjustedImage(forDisplay display: Int) -> CGImage? {",
            in: try code(of: Self.curlPath[0].url),
            missing: "`ReaderContainers.swift` no longer declares `adjustedImage(forDisplay:)`."
        )
    }

    @Test("Every sheet the curl draws is the page the decoder already produced")
    func sheetsComeFromTheDecoder() throws {
        let builder = try curlBuilder()
        for sheet in Self.sheets {
            #expect(
                builder.contains(sheet),
                """
                The curl no longer draws a `\(sheet)` sheet. `comic-reader` asks the curl to \
                turn the page that is already decoded, and it turns three of them: the page \
                in view, the one underneath it and the one behind it.
                """
            )
        }

        let decodes = builder.ranges(of: "adjustedImage(forDisplay:").count
        #expect(
            decodes == Self.sheets.count,
            """
            The curl builds \(Self.sheets.count) sheets from \(decodes) call(s) to \
            `adjustedImage(forDisplay:)`. `comic-reader` requires a curl over a comic to use \
            "the already-decoded page directly rather than a re-raster, because the page is \
            an image before the turn begins". A sheet fed from anywhere else is either a \
            second decode of a page the reader is already holding or a picture of the view, \
            and both cost a frame the finger is on.
            """
        )

        let adjusted = try adjustedImageBuilder()
        #expect(
            adjusted.ranges(of: "model.image(at:").count == 1,
            "`adjustedImage(forDisplay:)` no longer reads exactly one decoded page from the model."
        )
    }

    @Test("A curled sheet carries the series' border trim and sharpness")
    func sheetsCarryTrimAndSharpness() throws {
        let adjusted = try adjustedImageBuilder()
        #expect(
            adjusted.contains("cropped(image, when: trim.cropsBorders)"),
            "A curled sheet no longer crops the border trim every other container applies."
        )
        #expect(
            adjusted.contains("sharpened(") && adjusted.contains("trim.sharpness"),
            "A curled sheet no longer applies the sharpness every other container applies."
        )
    }

    @Test("The curl's own draw layer carries the series' colour adjustments")
    func curlCarriesColourAdjustments() throws {
        let curled = try curlBuilder()
        #expect(
            curled.contains("adjustments: adjustments"),
            """
            The curl is no longer handed the series' brightness, contrast, inversion and \
            greyscale. `comic-reader` "Persisting adjustments" applies to every container, \
            and the curl drew the raw decode while every other container applied this.
            """
        )
        let drawing = try code(of: Self.curlPath[1].url)
        #expect(
            drawing.contains(".adjusted(adjustments)"),
            "CurledPages no longer applies the colour adjustments to its own draw layer."
        )
    }

    /// The absence that the positive claim above cannot cover.
    ///
    /// Nothing here re-renders a view. `ImageRenderer` and a UIKit snapshot each produce a
    /// `CGImage`, so either would satisfy the parameter types and fail the requirement.
    @Test("Nothing on the curl's path turns a view back into a picture")
    func nothingReRasters() throws {
        for file in Self.curlPath {
            let code = try code(of: file.url)
            for rasteriser in ["ImageRenderer", "snapshot(", "drawHierarchy", "UIGraphics"] {
                #expect(
                    code.contains(rasteriser) == false,
                    """
                    \(file.name) reaches for `\(rasteriser)`. `comic-reader` requires the \
                    curl to take "the already-decoded page directly rather than a \
                    re-raster": the page is a `CGImage` before the turn begins, and \
                    rendering the view into a second one costs a full-page raster on the \
                    frame the finger lands.
                    """
                )
            }
        }
    }
}
