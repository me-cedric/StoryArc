import Foundation
import Testing

@testable import EpubReaderFeature
@testable import StoryArcCore

/// What the reflowable reader says a position is — on the menu, and out loud after a turn.
///
/// `ebook-reader`, *Progress display*: "one line states how far through the publication they
/// are and how much of the current chapter is left, in words", and "the app never presents a
/// reflowable page number as a stable identity".
///
/// `native-experience`, *Screen reader*: "the reader announces the page number and total on
/// each turn". A reflowable publication has no stable page number to announce, so this line is
/// what it announces instead — the same line the menu draws, because a position said one way
/// on screen and another way out loud is two positions.
@Suite("The reflowable position, in words")
struct EpubPositionSentenceTests {

    @Test("All three fragments, joined by punctuation")
    func theWholeLine() {
        let position = ReadingPositionLine(
            percentThrough: 42,
            chapter: "Chapter Three",
            chapterRemainder: .aboutHalfLeft
        )

        #expect(epubPositionSentence(position) == "42% read · Chapter Three, about half left")
    }

    /// Task 26.7: the line took the device language, not the one chosen in the app.
    @Test("The line reads in French on an English device")
    func theLineFollowsTheChosenLanguage() {
        let position = ReadingPositionLine(
            percentThrough: 42,
            chapter: "Chapter Three",
            chapterRemainder: .aboutHalfLeft
        )

        InterfaceLanguage.$scoped.withValue("fr") {
            #expect(epubPositionSentence(position) == "42% lu · Chapter Three, environ la moitié restante")
        }
    }

    @Test("A publication that names no chapter says only how far through")
    func noChapter() {
        let position = ReadingPositionLine(percentThrough: 7, chapter: nil, chapterRemainder: nil)

        #expect(epubPositionSentence(position) == "7% read")
    }

    @Test("A chapter Readium cannot measure keeps its name and drops the remainder")
    func noRemainder() {
        let position = ReadingPositionLine(
            percentThrough: 60,
            chapter: "Afterword",
            chapterRemainder: nil
        )

        #expect(epubPositionSentence(position) == "60% read · Afterword")
    }

    @Test("A turn changes the position even when the whole percentage does not")
    func everyTurnIsAChange() {
        let before = ReflowablePosition(progression: 0.4201, sentence: "42% read")
        let after = ReflowablePosition(progression: 0.4238, sentence: "42% read")

        #expect(
            before != after,
            """
            Two pages of one chapter compared equal, so `EpubPageTurnAccessibility` would \
            announce neither. The whole percentage is the same for both, which is exactly why \
            the progression is part of the value and the sentence alone is not.
            """
        )
    }
}
