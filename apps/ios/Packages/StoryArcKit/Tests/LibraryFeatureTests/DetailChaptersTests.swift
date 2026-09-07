import Foundation
import SwiftUI
import Testing

import DesignSystem
@testable import LibraryFeature
import Playback
import StoryArcCore

/// An audiobook's chapters, on its page rather than inside the player.
///
/// `audio-playback`, "Chapters before the first minute": "a listener SHALL be able to see an
/// audiobook's chapters without starting it, and SHALL be able to start at any one of them",
/// because "the player is reached by starting the book, so a listener choosing what to listen
/// to next could see a chapter list only by first playing something they had not chosen".
///
/// The rows are ``PlaybackPart``s — the same model the player's own `ChapterListView` draws —
/// so a title, a number and a length mean one thing in this app rather than two.
///
/// Android owes the mirror of every claim here; §11 of the task list carries both halves.
@Suite("Chapters on the publication page")
@MainActor
struct DetailChaptersTests {

    // MARK: - What the page is handed

    private func part(_ index: Int, _ title: String?, _ seconds: TimeInterval?) -> PlaybackPart {
        PlaybackPart(index: index, title: title, duration: seconds)
    }

    /// Three named chapters, as an M4B with markers reports them.
    private var chaptered: [PlaybackPart] {
        [part(0, "The Harbour", 600), part(1, "The Tide", 1_200), part(2, "The Reach", 900)]
    }

    /// Three unnamed parts, as `AudiobookReader.read(folderAt:)` reports every folder.
    private var folder: [PlaybackPart] {
        [part(0, nil, 600), part(1, nil, 600), part(2, nil, 600)]
    }

    private func listening(part index: Int, of count: Int, isFinished: Bool = false) -> ReadingProgress {
        ReadingProgress(
            identity: PublicationIdentity(contentDigest: "book"),
            position: .listening(part: index, partCount: count, offset: 30, of: 600),
            isFinished: isFinished,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - The list itself

    @Test("Every chapter is listed in order, with its title and its length")
    func titlesAndLengths() {
        let rows = DetailChapters.rows(of: chaptered, progress: nil)

        #expect(rows.map(\.index) == [0, 1, 2])
        #expect(rows.map(\.name) == [.given("The Harbour"), .given("The Tide"), .given("The Reach")])
        #expect(rows.map(\.duration) == [600, 1_200, 900])
    }

    /// The rule is `PlayerCentre.title(ofPartAt:)`'s, and a folder is why it matters: every
    /// part of one reaches the page with `title: nil`, so a page that drew titles alone would
    /// draw three blank rows.
    @Test("A part the container did not name is numbered, never blank")
    func unnamedPartsAreNumbered() {
        let rows = DetailChapters.rows(of: folder, progress: nil)

        #expect(rows.map(\.name) == [.numbered(1), .numbered(2), .numbered(3)])
    }

    @Test("The chapter stopped inside is in progress, and the ones behind it are finished")
    func theMarks() {
        let rows = DetailChapters.rows(of: chaptered, progress: listening(part: 1, of: 3))

        #expect(rows.map(\.mark) == [.finished, .inProgress, .unplayed])
    }

    @Test("A book never started marks nothing")
    func nothingMarked() {
        let rows = DetailChapters.rows(of: chaptered, progress: nil)

        #expect(rows.allSatisfy { $0.mark == .unplayed })
    }

    /// A finished book has no chapter left ahead of the listener, whatever position it
    /// stopped writing at — and it stops at the last part it played, not at the end.
    @Test("A finished audiobook marks every chapter finished")
    func finishedThroughout() {
        let rows = DetailChapters.rows(
            of: chaptered,
            progress: listening(part: 1, of: 3, isFinished: true)
        )

        #expect(rows.allSatisfy { $0.mark == .finished })
    }

    /// `reading-progress` keeps one position per publication, so a comic's page index shares
    /// the record an audiobook's part index would use. Reading one as the other would mark
    /// chapter 42 of a three-part book.
    @Test("A page position is never read as a chapter")
    func aPagePositionIsNotAPart() {
        let read = ReadingProgress(
            identity: PublicationIdentity(contentDigest: "book"),
            position: .page(index: 2, of: 40),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(DetailChapters.rows(of: chaptered, progress: read).allSatisfy { $0.mark == .unplayed })
    }

    // MARK: - The book with one part

    @Test("A single-part audiobook draws no list and states its own length")
    func onePartStatesItsLength() {
        let book = DetailChapters.of(.m4b, parts: [part(0, nil, 4_500)], progress: nil)

        #expect(book.chapters.isEmpty)
        #expect(book.length == 4_500)

        // The named single part is the one the count guard actually has to catch: an unnamed
        // one is dropped by the naming rule anyway, so a list built from every part would
        // still look empty here and the defect would ship.
        let named = DetailChapters.of(.m4b, parts: [part(0, "The Whole Book", 4_500)], progress: nil)
        #expect(named.chapters.isEmpty, "A book of one part grew a list of one row")
        #expect(named.length == 4_500)
    }

    /// "The whole book's length, or `nil` when any part's is unknown" — a total assembled from
    /// the parts that answered would be a number shorter than the book.
    @Test("A book with a part of unknown length states no length")
    func partialLengthsStateNothing() {
        #expect(DetailChapters.duration(of: [part(0, nil, 600), part(1, nil, nil)]) == nil)
        #expect(DetailChapters.duration(of: []) == nil)
        #expect(DetailChapters.duration(of: chaptered) == 2_700)
    }

    // MARK: - What a comic gets

    /// The guard lives in ``DetailChapters/of(_:parts:progress:)`` rather than at the call
    /// site, so a second surface composing the column cannot forget it.
    @Test("A comic never grows a chapter list")
    func comicsHaveNoChapters() {
        for format in PublicationFormat.allCases where !format.isAudio {
            let book = DetailChapters.of(format, parts: chaptered, progress: listening(part: 1, of: 3))

            #expect(book == .absent, "\(format) was given an audiobook's chapter list")
        }
    }

    // MARK: - The read the page actually performs

    /// Walks up from this file to the committed fixture corpus.
    ///
    /// `#filePath` rather than a walk from the working directory, for ``LibraryFeatureSource``'s
    /// reason: this repository nests agent worktrees at `.claude/worktrees/`, and a walk climbs
    /// out of the checkout under test.
    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let corpus = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: corpus.appending(path: "manifest.json").path) {
                return corpus
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found — expected packages/test-fixtures above \(#filePath)")
    }()

    /// **The read is the wiring, and until now nothing watched it.** Every claim above is made
    /// against a part list a test built. Returning ``DetailAudiobook/absent`` from the top of
    /// ``DetailChapters/read(_:at:progress:)`` left all 578 tests in this target green, and the
    /// page then held no chapter on any device.
    ///
    /// The corpus file, not a stub: `AudiobookReader` and ``PlaybackTimeline`` are between the
    /// page and the container, so a chapter marker this project cannot read is a chapter the
    /// page cannot draw. `AudiobookReaderTests` asserts the same three chapters of the same
    /// file, and Android reads it too.
    @Test("The page reads an audiobook's chapters off the file itself")
    func theFileIsRead() async {
        let book = await DetailChapters.read(
            Publication(
                identity: PublicationIdentity(contentDigest: "book"),
                format: .m4b,
                displayTitle: "Tidal Reach",
                origin: .inferred
            ),
            at: Self.corpus.appending(path: "audiobooks/chaptered.m4b"),
            progress: nil
        )

        #expect(
            book.chapters.map(\.name) == [.given("One"), .given("Two"), .given("Three")],
            "The page read no chapter off a file that has three."
        )
        #expect(book.length == 6, "The page states a length no part of the file supports.")
    }

    // MARK: - What the primary action promises

    @Test("The action names the chapter it resumes inside")
    func theActionNamesTheChapter() {
        let book = DetailChapters.of(.m4b, parts: chaptered, progress: listening(part: 2, of: 3))

        #expect(book.resuming == .given("The Reach"))
        #expect(
            PrimaryAction.of(.m4b, hasProgress: true, chapter: book.resuming)
                == .resumeChapter(.given("The Reach"))
        )
    }

    @Test("An unnamed part is resumed by its number")
    func theActionNumbersAnUnnamedPart() {
        let book = DetailChapters.of(.audioFolder, parts: folder, progress: listening(part: 1, of: 3))

        #expect(book.resuming == .numbered(2))
    }

    /// "An audiobook never started offers to start it, naming no chapter" — and a book of one
    /// unnamed part has no chapter to name even once it has been started, because "Part 1 of
    /// 1" is a number a listener cannot use.
    @Test("A book never started, and a book of one part, name no chapter")
    func noChapterToName() {
        #expect(DetailChapters.of(.m4b, parts: chaptered, progress: nil).resuming == nil)
        #expect(PrimaryAction.of(.m4b, hasProgress: false, chapter: nil) == .listen)

        let single = DetailChapters.of(.m4b, parts: [part(0, nil, 4_500)], progress: listening(part: 0, of: 1))
        #expect(single.resuming == nil)
        #expect(PrimaryAction.of(.m4b, hasProgress: true, chapter: single.resuming) == .continueListening)
    }

    // MARK: - How a length is said

    /// Two forms, and the difference is the point: `12:34` is right on the face of a row and
    /// wrong in a screen reader, which reads it "twelve colon thirty four".
    ///
    /// ``PlaybackClock`` states both, because the player states the same two forms of the same
    /// lengths — the arithmetic was written out twice, byte for byte, until 2026-09-07.
    @Test("A length is written as a clock and spoken as words")
    func lengthsAreSaidTwice() {
        #expect(PlaybackClock.time(754) == "12:34")
        #expect(PlaybackClock.time(3_750) == "1:02:30")
        #expect(PlaybackClock.time(0) == "0:00")

        let spoken = PlaybackClock.spokenTime(754)
        #expect(!spoken.contains(":"), "A screen reader was handed a clock face: \(spoken)")
    }

    // MARK: - The page composes it

    /// **Measured rather than predicated**, for ``KavitaCardFactsTests``' reason: a list that
    /// returns an empty `VStack` satisfies "draws no rows" and still leaves a band of nothing
    /// under the primary action of every comic on the shelf.
    @Test("A publication with no chapters to state takes no room")
    func nothingToSayTakesNoRoom() {
        #expect(stacked(.absent) == descriptionAlone)
    }

    @Test("An audiobook's chapters are drawn where the page composes them")
    func chaptersAreDrawn() {
        let book = DetailChapters.of(.m4b, parts: chaptered, progress: nil)

        #expect(stacked(book) > descriptionAlone)
    }

    /// The wiring, which is where the defect would live. A list that draws its rows perfectly
    /// proves nothing if the column never calls it, and deleting that one call leaves every
    /// other test in this file green — ``KavitaCardFactsTests`` names the same reason for the
    /// same seam.
    @Test("The page's own column draws the chapters")
    func theColumnDrawsThem() {
        let book = DetailChapters.of(.m4b, parts: chaptered, progress: nil)

        #expect(height(of: column(book), width: 360) > height(of: column(.absent), width: 360))
    }

    /// The other half of the wiring, and it is a declaration rather than a value: the label is
    /// a `Text`, so a column that stopped handing the chapter over would still draw a button
    /// and every assertion above would stay green. ``PublicationPaneTests`` reads source for
    /// the same reason.
    @Test("The action is handed the chapter the page found")
    func theActionIsHandedTheChapter() {
        let code = LibraryFeatureSource.code(of: "Sources/LibraryFeature/DetailMainColumn.swift")

        #expect(
            code.contains("resuming: audiobook.resuming"),
            "The column no longer tells the primary action which chapter it would resume inside."
        )

        let action = LibraryFeatureSource.code(of: "Sources/LibraryFeature/DetailActions.swift")
        #expect(
            action.contains("chapter: resuming"),
            "The primary action no longer asks PrimaryAction for the chapter, so it says Continue instead of naming it."
        )
    }

    /// §11.6: one row per chapter, with the length as the row's *value*. Read as source for
    /// the reason above — an accessibility declaration draws no pixel, so nothing this suite
    /// can render would notice it going away.
    @Test("A row is one element to a screen reader, and its length is its value")
    func theRowIsOneElementWithAValue() {
        let code = LibraryFeatureSource.code(of: "Sources/LibraryFeature/DetailChapterList.swift")

        #expect(
            code.contains(".accessibilityElement(children: .combine)"),
            "A chapter row is no longer one element, so a screen reader reads its glyph apart from its title."
        )
        #expect(
            code.contains(".accessibilityValue(Text(chapter.duration.map(PlaybackClock.spokenTime)"),
            "A chapter row no longer states its length as its value, in words."
        )
    }

    /// The list ships in every language the app does, or it ships a key on a reader's screen.
    @Test("Every word this list adds is translated everywhere the app ships")
    func theWordsAreTranslated() {
        let keys = [
            "detail.chapters",
            "detail.chapter.number %lld",
            "detail.chapter.finished",
            "detail.duration %@",
            "detail.continueListening.in %@",
        ]
        for key in keys {
            let languages = LibraryFeatureSource.localizationsIfAny(of: key)
            #expect(languages != nil, "the catalogue answers nothing for \(key)")
            for language in ["de", "en", "es", "fr"] {
                #expect(languages?[language] != nil, "\(key) has no \(language)")
            }
        }
    }

    private func column(_ book: DetailAudiobook) -> DetailMainColumn {
        DetailMainColumn(
            publication: Publication(
                identity: PublicationIdentity(contentDigest: "book"),
                format: .m4b,
                displayTitle: "Tidal Reach",
                origin: .inferred
            ),
            model: LibraryModel(),
            cover: nil,
            isKept: .constant(false),
            kavitaCard: nil,
            file: nil,
            audiobook: book,
            onChooseChapter: nil,
            onRead: {}
        )
    }

    private func height(of content: some View, width: CGFloat) -> CGFloat {
        let renderer = ImageRenderer(content: content.frame(width: width))
        var measured = CGSize.zero
        renderer.render { size, _ in measured = size }
        return measured.height
    }

    /// The two new parts of the column, stacked under a description the way the column stacks
    /// them.
    private func stacked(_ book: DetailAudiobook) -> CGFloat {
        height(
            of: VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                Text(verbatim: "A harbour town, described by the file it came in.")
                DetailChapterList(chapters: book.chapters, onChoose: nil)
                if book.chapters.isEmpty {
                    DetailBookLength(seconds: book.length)
                }
            },
            width: 320
        )
    }

    private var descriptionAlone: CGFloat {
        height(
            of: VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                Text(verbatim: "A harbour town, described by the file it came in.")
            },
            width: 320
        )
    }
}
