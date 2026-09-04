import Foundation
import Testing

@testable import DesignSystem
import StoryArcCore

/// One treatment for a missing cover, on every surface that draws one.
///
/// The September sweep counted three: the publication's own title on the shelf, a book glyph
/// with the format on its page, and a flat grey square with the title in the player — "the
/// app says the artwork is the interface; this is what it does when there is none, in three
/// unrelated ways". A fourth complaint rode on the second: an *audiobook* was given the book
/// glyph.
///
/// Two halves are asserted here and they fail for different reasons.
///
/// - **The mapping.** Every format has a symbol, and the symbol groups formats by what a
///   reader does with them rather than by which container they arrived in. Pure, so it needs
///   no window.
/// - **The reach.** Every surface that draws a cover-shaped well asks ``CoverlessWell`` for
///   it. That half reads source text, which is the trade `GlassIsUntintedTests` and
///   `AccentReachesTheControlsTests` make and explain: composing these views needs a
///   simulator and `swift test` runs on the host. It cannot see a rendered pixel; it can see
///   the surface that stopped sharing the treatment, which is the thing that regressed —
///   and this defect *is* a regression of exactly that shape, three times over.
@Suite("Coverless well")
struct CoverlessWellTests {

    // MARK: - The mapping

    @Test("Every format the app knows has a glyph", arguments: PublicationFormat.allCases)
    func everyFormatHasAGlyph(format: PublicationFormat) {
        #expect(!coverlessWellSymbol(for: format).isEmpty)
    }

    /// The sweep's own complaint, pinned: `ios-detail-audiobook.png` is a book glyph over the
    /// word *Audiobook*.
    @Test(
        "An audiobook is never drawn as a book",
        arguments: [PublicationFormat.audiobook, .audioFolder]
    )
    func audioIsNeverABook(format: PublicationFormat) {
        let symbol = coverlessWellSymbol(for: format)
        #expect(!symbol.hasPrefix("book"))
        #expect(symbol == coverlessWellSymbol(for: .audiobook))
    }

    /// A publication read page by page, one read as text, one that is a document and one
    /// listened to are four different things to a reader, and the well is the only place that
    /// difference can be seen before opening it.
    @Test("The four kinds are told apart")
    func theFourKindsAreDistinct() {
        let kinds = [
            coverlessWellSymbol(for: .cbz),
            coverlessWellSymbol(for: .epub),
            coverlessWellSymbol(for: .pdf),
            coverlessWellSymbol(for: .audiobook),
        ]
        #expect(Set(kinds).count == kinds.count)
    }

    /// Every comic container is one publication to a reader. A CBZ and a CBT differ in how
    /// the bytes are packed and in nothing a reader can see — the *name* under the glyph is
    /// where that difference is stated, because that is the half that can be exact.
    @Test(
        "Every comic container shares one glyph",
        arguments: [PublicationFormat.cbr, .cb7, .cbt, .imageFolder]
    )
    func comicsShareAGlyph(format: PublicationFormat) {
        #expect(coverlessWellSymbol(for: format) == coverlessWellSymbol(for: .cbz))
    }

    // MARK: - The reach

    /// The package directory, from this test's own compiled path.
    ///
    /// `#filePath` and not a walk up from the working directory: this repository nests agent
    /// worktrees at `.claude/worktrees/<name>/`, and a walk that climbs looking for a marker
    /// leaves the checkout under test and guards the parent's copy.
    private static let package: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DesignSystemTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // StoryArcKit

    /// Every surface in the app that draws a cover-shaped well with nothing in it.
    ///
    /// The app target is here as well as the two features, and that is deliberate: the
    /// downloads destination draws its own grid outside the package, and a guard that stopped
    /// at the package boundary is how a fourth treatment would arrive next.
    private static let surfaces: [(what: String, path: String)] = [
        ("the shelf's grid cell", "Sources/LibraryFeature/CoverCell.swift"),
        ("Home's shelves and hero", "Sources/LibraryFeature/HomeArtwork.swift"),
        ("the publication page's hero", "Sources/LibraryFeature/DetailHero.swift"),
        ("the player's artwork", "Sources/PlayerFeature/PlayerArtwork.swift"),
        ("the on-device shelf", "../../App/OnDeviceShelf.swift"),
    ]

    private func code(of path: String) throws -> String {
        let file = Self.package.appending(path: path)
        let text = try #require(
            try? String(contentsOf: file, encoding: .utf8),
            "\(file.path) could not be read — has the surface moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    @Test("Every surface with a well asks for the shared one")
    func everySurfaceDrawsTheSharedWell() throws {
        for surface in Self.surfaces {
            let source = try code(of: surface.path)
            #expect(
                source.contains("CoverlessWell("),
                """
                \(surface.what) does not draw `CoverlessWell`. A publication with no artwork \
                had three unrelated fallbacks before this view moved to `DesignSystem`, and \
                the reason the player had its own was a module edge that no longer exists: \
                `LibraryFeature`, `PlayerFeature` and the app target all depend on \
                `DesignSystem` already.
                """
            )
        }
    }

    /// No surface draws a placeholder glyph of its own any more.
    ///
    /// The publication page held `Image(systemName: "book.closed")` beside the format, and
    /// the player held `Image(systemName: "headphones")` before that — with a comment
    /// claiming it was "the same placeholder the library draws", which it was not. A guard
    /// on the *spelling* is what would have caught either.
    @Test("No surface draws a coverless glyph of its own")
    func noSurfaceDrawsItsOwnGlyph() throws {
        for surface in Self.surfaces {
            let source = try code(of: surface.path)
            for glyph in ["book.closed", "headphones", "book.pages", "doc.text"] {
                #expect(
                    !source.contains("systemName: \"\(glyph)\""),
                    """
                    \(surface.what) draws `\(glyph)` itself. The glyph for a publication with \
                    no artwork is `coverlessWellSymbol(for:)`'s to choose, so that an \
                    audiobook cannot be given a book on one screen and headphones on another \
                    — which is what the September sweep photographed.
                    """
                )
            }
        }
    }
}
