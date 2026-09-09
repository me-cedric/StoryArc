import Foundation
import Testing

@testable import LibraryFeature
import Playback
import StoryArcCore

/// What the publication page's list says is left of the chapter in progress.
///
/// `audio-playback`, "Chapters": the chapter in progress "also states how much of itself is
/// left, so a listener can tell a chapter they have just begun from one they are about to
/// finish", on "the player and the publication's page alike".
///
/// A file of its own rather than more of ``DetailChaptersTests``, which sits at the 400-line
/// cap `pnpm lines:check` enforces.
///
/// **Proved able to fail**, per AGENTS.md §5, one mutation per test: reading the rows at
/// offset `0` rather than at the recorded one, reading a chapter with no length as zero
/// seconds, `restated(at:)` answering `self` for a place it was given, `restated(at: nil)`
/// reading no place as the start of the book, the page passing `audiobook` rather than
/// `audiobook.restated(at: playingPlace)`, the page asking `centre.isRunning` rather than
/// whose audio is playing, the row's `if let remaining` block deleted, the mark in progress
/// silenced, the glyph hard-coded, the row's facts moved back inside the button's label, the
/// printed length allowed to speak, and the `typeSize.isAccessibilitySize` branch deleted.
/// Each failed its own test by name, and each was reverted.
@Suite("What is left of a chapter, on the publication page")
struct DetailChapterRemainderTests {

    private func part(_ index: Int, _ seconds: TimeInterval?) -> PlaybackPart {
        PlaybackPart(index: index, title: nil, duration: seconds)
    }

    /// Stopped 30 seconds into the named part, which is what `reading-progress` records.
    private func listening(part index: Int, of count: Int) -> ReadingProgress {
        ReadingProgress(
            identity: PublicationIdentity(contentDigest: "book"),
            position: .listening(part: index, partCount: count, offset: 30, of: 600),
            isFinished: false,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("Only the chapter in progress states a remainder, and it is what is left of that chapter")
    func onlyTheChapterInProgressStatesARemainder() {
        let chaptered = [part(0, 600), part(1, 1_200), part(2, 900)]

        let rows = DetailChapters.rows(of: chaptered, progress: listening(part: 1, of: 3))

        #expect(rows[1].remaining == 1_170, "The chapter in progress does not state what is left of it.")
        #expect(rows[0].remaining == nil, "A finished chapter states a remainder it cannot have.")
        #expect(rows[2].remaining == nil, "A chapter not yet reached states a remainder.")
    }

    @Test("A chapter whose length the container never stated states no remainder")
    func anUnmeasuredChapterStatesNoRemainder() {
        let unmeasured = [part(0, nil), part(1, nil)]

        let rows = DetailChapters.rows(of: unmeasured, progress: listening(part: 1, of: 2))

        #expect(rows.allSatisfy { $0.duration == nil }, "A part nothing measured was given a length.")
        #expect(rows.allSatisfy { $0.remaining == nil }, "A part nothing measured was given a remainder.")
    }

    /// The page is not a snapshot while the book it shows is playing.
    ///
    /// Measured on 2026-09-09: the rows were read once, when the page appeared, so a page left
    /// open stated `18:00 left` on a chapter the audio had left twenty minutes earlier and went
    /// on marking that chapter as the one in progress. `audio-playback` asks the same statement
    /// of "the player and the publication's page alike".
    @Test("A page open while the book plays restates its rows from where the audio is")
    func theRowsFollowTheAudio() {
        let stored = book(at: 0)

        let live = stored.restated(at: PlaybackPlace(partIndex: 2, offset: 300))

        #expect(live.chapters.map(\.mark) == [.finished, .finished, .inProgress])
        #expect(live.chapters[2].remaining == 600, "The row in progress does not count down with the audio.")
        #expect(live.chapters[0].remaining == nil, "A chapter the audio has passed states a remainder.")
    }

    @Test("A page whose publication is not playing keeps the rows the record made")
    func nothingPlayingLeavesTheRowsAlone() {
        let stored = book(at: 1)

        #expect(stored.restated(at: nil) == stored)
    }

    /// The wiring, which is where this defect lived: the rule can be right and the page can
    /// still draw the snapshot. Read as source because a page needs a window to compose.
    @Test("The page draws the rows the session restated")
    func thePageAsksWhereTheAudioIs() {
        let page = LibraryFeatureSource.code(of: "Sources/LibraryFeature/PublicationDetailView.swift")

        #expect(
            page.contains("audiobook.restated(at: playingPlace)"),
            "The page draws the rows it read once, so its remainder freezes while the book plays."
        )
        #expect(
            page.contains("centre.book?.id == publication.id"),
            "The page no longer asks whether the session is playing *this* publication."
        )
    }

    /// The row draws it, and that is a second question from whether the rule answers.
    ///
    /// Measured on 2026-09-09: deleting the row's `if let remaining` block left this suite and
    /// ``DetailChaptersTests`` green, because both read values and neither reads the view.
    @Test("The page's row draws what is left of the chapter in progress")
    func theRowDrawsTheRemainder() {
        let list = LibraryFeatureSource.code(of: "Sources/LibraryFeature/DetailChapterList.swift")

        #expect(
            list.contains("if let remaining = chapter.remaining"),
            "The row no longer reads the remainder, so the chapter in progress states nothing left."
        )
        #expect(
            list.contains("remainder(remaining)"),
            "The row reads the remainder and draws nothing with it."
        )
    }

    /// What the row says about its mark, and where it says it.
    ///
    /// Measured on 2026-09-09: the mark in progress had only an `isSelected` trait to carry it,
    /// and that trait sat inside the button's label where it reached nothing — so a screen
    /// reader stated no mark on that row while every finished row above it said "Finished".
    /// The printed length was the other half: it joined the combined label, so the row stated
    /// its length twice and once as a clock face.
    @Test("The mark in progress carries a word, and the row's facts sit on the button")
    func theMarkInProgressIsSpoken() {
        let list = LibraryFeatureSource.code(of: "Sources/LibraryFeature/DetailChapterList.swift")

        #expect(
            list.contains("Text(\"detail.chapter.inProgress\", bundle: .module)"),
            "The mark in progress is a silent glyph, so a screen reader states no mark on that row."
        )
        #expect(
            list.contains("Image(systemName: mark.glyph)"),
            "The row draws a glyph of its own choosing rather than the mark's, so it can draw one no rule chose."
        )
        #expect(
            list.contains("stated(chapter, button.buttonStyle(.plain), isChoosable: true)"),
            "The row's value and traits are back inside the button's label, where neither reaches a reader."
        )
        #expect(
            !list.contains(".isSelected"),
            "The row states its mark twice: the glyph says the word and the trait says it again."
        )
        #expect(
            list.contains("isChoosable ? .isButton : []"),
            "A row the page cannot start still calls itself a button, so a reader is offered a dead action."
        )
        #expect(
            list.filter { !$0.isWhitespace }.contains(".monospacedDigit().accessibilityHidden(true)"),
            "The printed length speaks again, so the row states its length twice and once as a clock face."
        )
    }

    /// The page re-reads the record when the session that owns the book ends.
    ///
    /// ``PublicationDetailView/playingPlace`` restates the rows while a session runs and
    /// answers `nil` the moment it stops. Measured on 2026-09-09: the page then fell back to
    /// the record it read when it appeared, which could be an hour of listening old. The
    /// session writes its position as it ends, so the read has to run again exactly then.
    @Test("The chapter read runs again when the book stops playing")
    func theReadRunsAgainWhenTheSessionEnds() {
        let view = LibraryFeatureSource.code(of: "Sources/LibraryFeature/PublicationDetailView.swift")

        #expect(
            view.contains(".task(id: ChapterInputs(file: file, isPlaying: playingPlace != nil))"),
            "The chapter read is keyed on the file alone, so the page keeps the rows it appeared with."
        )
    }

    /// Four items on one row do not fit at the accessibility sizes.
    ///
    /// The project photographed this failure on 2026-09-05 for a row of *two*: a settings value
    /// read `Not an-swering` across three lines of a column a few characters wide, and
    /// `SourceDetail.swift` stacks at `isAccessibilitySize` because of it. This row carries a
    /// mark, a title, a remainder and a length.
    ///
    /// **This asserts the branch, and a photograph asserts the fit** — the division
    /// `SourceDetailSizeTests` draws for the same guard.
    @Test("The row stacks rather than sharing one line at the accessibility sizes")
    func theRowStacksWhenTheTextIsLargest() {
        let list = LibraryFeatureSource.code(of: "Sources/LibraryFeature/DetailChapterList.swift")

        #expect(
            list.contains("typeSize.isAccessibilitySize"),
            "The row does not ask the text size, so four items share one line at every size."
        )
        #expect(
            list.contains("@Environment(\\.dynamicTypeSize)"),
            "The list cannot ask the text size: it does not read it from the environment."
        )
    }

    /// Three chapters of 10, 20 and 15 minutes, stopped 30 seconds into the one named.
    private func book(at index: Int) -> DetailAudiobook {
        let chaptered = [part(0, 600), part(1, 1_200), part(2, 900)]
        return DetailAudiobook(
            chapters: DetailChapters.rows(of: chaptered, progress: listening(part: index, of: 3)),
            length: DetailChapters.duration(of: chaptered),
            resuming: nil
        )
    }
}
