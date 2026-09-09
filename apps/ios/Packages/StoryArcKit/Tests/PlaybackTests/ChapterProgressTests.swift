import Foundation
import Testing

@testable import Playback

/// The three marks and the remainder, as arithmetic with no list around them.
///
/// `audio-playback`, "Chapters": "a chapter already finished is marked as finished, a chapter
/// not yet reached carries no mark, and the chapter in progress is marked as the one in
/// progress", and that chapter "also states how much of itself is left, so a listener can tell
/// a chapter they have just begun from one they are about to finish".
///
/// The rule is here rather than beside either list because the spec asks it of "every surface
/// that lists chapters", and because the two surfaces disagreed while each owned its own copy:
/// measured on 2026-09-08, the publication page marked three states and the player marked one.
///
/// **Proved able to fail**, per AGENTS.md §5, one mutation per test: `index < reached`
/// returning `.unplayed`, the `reached == nil` guard returning `.finished`, `isFinished`
/// returning `.inProgress`, the `mark == .inProgress` guard in `remainder` becoming
/// `mark == .finished`, `remainder` dropping the offset, `remainder` answering
/// `max(0, (length ?? 0) - offset)` for a chapter with no length, `remainder` dropping its
/// floor at zero, and each of the three glyph names in turn. Each failed its own test by name,
/// and each was reverted.
@Suite("A chapter's progress")
struct ChapterProgressTests {

    @Test("A chapter behind the listener is finished, the one under them is in progress, and one ahead is unmarked")
    func theThreeMarks() {
        let marks = (0..<3).map { ChapterProgress.mark(of: $0, reached: 1, isFinished: false) }

        #expect(marks == [.finished, .inProgress, .unplayed])
    }

    @Test("A book never listened to marks nothing")
    func nothingReachedMarksNothing() {
        let marks = (0..<3).map { ChapterProgress.mark(of: $0, reached: nil, isFinished: false) }

        #expect(marks.allSatisfy { $0 == .unplayed })
    }

    @Test("A book recorded finished leaves no chapter ahead of the listener")
    func aFinishedBookIsFinishedThroughout() {
        let marks = (0..<3).map { ChapterProgress.mark(of: $0, reached: 1, isFinished: true) }

        #expect(marks.allSatisfy { $0 == .finished })
    }

    @Test("The chapter in progress states how much of itself is left")
    func theRemainderIsWhatIsLeft() {
        #expect(left(of: 1_200, .inProgress, at: 288) == 912)
        #expect(left(of: 1_200, .inProgress, at: 0) == 1_200)
    }

    /// The gate the player's row used to hold itself, which is why it is here.
    ///
    /// Measured on 2026-09-09: `mark == .inProgress` in the row became `mark == .finished`, so
    /// the chapter in progress stated no remainder and every finished chapter stated one, and
    /// the suite passed. The gate is a requirement — "the chapter in progress *also* states how
    /// much of itself is left" — and a requirement inside a view body is one nothing checks.
    @Test("No chapter but the one in progress states a remainder")
    func onlyTheChapterInProgressStatesARemainder() {
        #expect(left(of: 1_200, .finished, at: 288) == nil)
        #expect(left(of: 1_200, .unplayed, at: 0) == nil)
    }

    @Test("A chapter whose length the container never stated states no remainder")
    func anUnmeasuredChapterStatesNothing() {
        #expect(left(of: nil, .inProgress, at: 30) == nil)
    }

    @Test("A chapter reported past its own end states no negative time")
    func theRemainderNeverGoesBelowZero() {
        #expect(left(of: 600, .inProgress, at: 601) == 0)
    }

    /// The glyph each mark is drawn as.
    ///
    /// Held on the mark rather than in each list's `switch`, and asserted here, because a glyph
    /// name inside a view body is a name nothing reads: measured on 2026-09-09, a hard-coded
    /// circle replaced the player row's mark and `PlayerChapterListTests` still passed with
    /// every row drawing the unplayed glyph.
    ///
    /// The three are separate symbols rather than three tints of one: `accessibility` requires
    /// a state to be readable without colour, and a listener who cannot separate the accent
    /// from the text colour has only the shape.
    @Test("Each mark is drawn as its own symbol")
    func eachMarkHasItsOwnGlyph() {
        #expect(ChapterMark.finished.glyph == "checkmark.circle.fill")
        #expect(ChapterMark.inProgress.glyph == "speaker.wave.2.fill")
        #expect(ChapterMark.unplayed.glyph == "circle")
        #expect(Set([ChapterMark.finished, .inProgress, .unplayed].map(\.glyph)).count == 3)
    }

    private func left(of length: TimeInterval?, _ mark: ChapterMark, at offset: TimeInterval) -> TimeInterval? {
        ChapterProgress.remainder(ofChapterLasting: length, mark: mark, at: offset)
    }
}
