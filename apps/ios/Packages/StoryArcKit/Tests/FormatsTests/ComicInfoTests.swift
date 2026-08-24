import Foundation
import StoryArcCore
import Testing

@testable import Formats

/// Asserted against the shared corpus. Android's `ComicInfoTest` reads the same
/// manifest entries, so neither platform can privately decide what a field means.
@Suite("ComicInfo metadata")
struct ComicInfoTests {
    private func comicInfo(_ name: String) async throws -> ComicInfo {
        let archive = try await ComicArchiveOpener.open(
            fileAt: FixtureCorpus.url("comics/\(name)")
        )
        let zip = try #require(archive as? ZipComicArchive)
        let data = try #require(zip.comicInfoData)
        return try #require(ComicInfo(data: data))
    }

    @Test("Every field the spec names is read")
    func allFields() async throws {
        let info = try await comicInfo("manga-metadata.cbz")
        #expect(info.series == "Fixture Manga")
        #expect(info.number == "3")
        #expect(info.volume == 2)
        #expect(info.title == "The Third Chapter")
        #expect(info.pencillers == ["A Penciller"])
        #expect(info.publisher == "Fixture Press")
        #expect(info.year == 2026)
        #expect(info.month == 1)
        #expect(info.day == 15)
        #expect(info.pageCount == 4)
        #expect(info.language == "ja")
    }

    @Test("A creator field holds a list, because ComicInfo allows one")
    func creatorLists() async throws {
        let info = try await comicInfo("manga-metadata.cbz")
        #expect(info.writers == ["First Writer", "Second Writer"])
    }

    @Test("XML entities in text are decoded")
    func entitiesDecoded() async throws {
        let info = try await comicInfo("manga-metadata.cbz")
        // Showing `&amp;` in a library is a bug a user sees immediately.
        #expect(info.summary == "A summary with an & in it, to prove entities are decoded.")
    }

    @Test("The issue number stays a string")
    func numberIsAString() {
        // "3.5" and "Annual 1" are both real issue numbers, and rounding either
        // loses the publication's identity.
        let info = ComicInfo(data: Data("<ComicInfo><Number>3.5</Number></ComicInfo>".utf8))
        #expect(info?.number == "3.5")
    }

    // MARK: - Reading direction

    @Test("An explicit right-to-left declaration is honoured")
    func declaredRightToLeft() async throws {
        let info = try await comicInfo("manga-metadata.cbz")
        #expect(info.declaredDirection == .rightToLeft)
        #expect(info.readingDirection == .rightToLeft)
    }

    @Test("Japanese with no declared direction opens right-to-left")
    func japaneseWithoutDeclaration() async throws {
        let info = try await comicInfo("japanese-no-direction.cbz")
        #expect(info.declaredDirection == nil)
        #expect(info.language == "ja-JP")
        // The second branch of the rule, and the one a reader most often gets
        // wrong by keying on the wrong field.
        #expect(info.readingDirection == .rightToLeft)
    }

    @Test("Manga=Yes does not declare a direction on its own")
    func mangaYesIsNotADeclaration() {
        // It says the publication is manga, which is not the same as saying which
        // way it reads — plenty of manga are published left-to-right in
        // translation. So it falls through to the language rule.
        let english = ComicInfo(
            data: Data("<ComicInfo><Manga>Yes</Manga><LanguageISO>en</LanguageISO></ComicInfo>".utf8)
        )
        #expect(english?.declaredDirection == nil)
        #expect(english?.readingDirection == .leftToRight)
    }

    @Test("Manga=No declares left-to-right, overriding the language")
    func mangaNoOverridesLanguage() {
        let info = ComicInfo(
            data: Data("<ComicInfo><Manga>No</Manga><LanguageISO>ja</LanguageISO></ComicInfo>".utf8)
        )
        #expect(info?.declaredDirection == .leftToRight)
        #expect(info?.readingDirection == .leftToRight)
    }

    @Test("No metadata at all means left-to-right")
    func nothingDeclared() {
        let info = ComicInfo(data: Data("<ComicInfo></ComicInfo>".utf8))
        #expect(info?.readingDirection == .leftToRight)
    }

    // MARK: - The Pages list

    @Test("A designated cover that is not page 1 is read")
    func designatedCover() async throws {
        let info = try await comicInfo("manga-metadata.cbz")
        // `publication-formats`: the first page in reading order is the cover
        // *unless* ComicInfo designates another.
        #expect(info.coverPageIndex == 1)
    }

    @Test("Designating page 0 as the cover is not treated as an override")
    func defaultCoverIsNotAnOverride() {
        // Index 0 is already the default, so a well-formed file that states it
        // must not look like it is asking for something different.
        let info = ComicInfo(
            data: Data("""
            <ComicInfo><Pages><Page Image="0" Type="FrontCover"/></Pages></ComicInfo>
            """.utf8)
        )
        #expect(info?.coverPageIndex == nil)
    }

    @Test("Double-page spreads are believed rather than guessed")
    func doublePages() async throws {
        let info = try await comicInfo("manga-metadata.cbz")
        // `PageDecoder.isSpread` is a heuristic over aspect ratio; this is a
        // statement by whoever made the file, so it wins.
        #expect(info.doublePageIndices == [2])
    }

    // MARK: - Robustness

    @Test("Bytes that are not ComicInfo yield nothing")
    func notComicInfo() {
        #expect(ComicInfo(data: Data("<Something/>".utf8)) == nil)
        #expect(ComicInfo(data: Data(repeating: 0xFF, count: 64)) == nil)
    }

    @Test("A ComicInfo with only a series still parses")
    func minimalFile() {
        // Common in real libraries, and a parser that requires more finds nothing.
        let info = ComicInfo(data: Data("<ComicInfo><Series>Only This</Series></ComicInfo>".utf8))
        #expect(info?.series == "Only This")
        #expect(info?.number == nil)
        #expect(info?.doublePageIndices.isEmpty == true)
    }

    @Test("An empty element is absent rather than an empty string")
    func emptyElementsAreNil() {
        let info = ComicInfo(data: Data("<ComicInfo><Series>   </Series></ComicInfo>".utf8))
        #expect(info?.series == nil)
    }

    @Test("A non-numeric year does not become a number")
    func malformedNumbers() {
        let info = ComicInfo(data: Data("<ComicInfo><Year>MMXXVI</Year></ComicInfo>".utf8))
        #expect(info?.year == nil)
    }
}
