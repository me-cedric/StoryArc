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

    /// Just the property that builds the curl.
    ///
    /// The file holds the other three containers too, and each of them reads a decoded page
    /// as well. Counting over the whole file would pass while the curl read none.
    private func curlBuilder() throws -> String {
        let container = try code(of: Self.curlPath[0].url)
        let opening = try #require(
            container.range(of: "var curled: some View {"),
            "`ReaderContainers.swift` no longer declares `var curled` — has the curl moved?"
        )
        let rest = container[opening.upperBound...]
        let closing = try #require(
            rest.range(of: "\n    }"),
            "`var curled` is not closed where this guard expects it."
        )
        return String(rest[..<closing.lowerBound])
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

        let decodes = builder.ranges(of: "model.image(at:").count
        #expect(
            decodes == Self.sheets.count,
            """
            The curl builds \(Self.sheets.count) sheets from \(decodes) call(s) to \
            `model.image(at:)`. `comic-reader` requires a curl over a comic to use "the \
            already-decoded page directly rather than a re-raster, because the page is an \
            image before the turn begins". A sheet fed from anywhere else is either a second \
            decode of a page the reader is already holding or a picture of the view, and \
            both cost a frame the finger is on.
            """
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
