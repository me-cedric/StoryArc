import Foundation
import Testing

@testable import LibraryFeature
import Playback
import StoryArcCore

/// What the publication page's one primary action says.
///
/// `publication-detail` makes the wording an accessibility requirement rather than a
/// preference: exactly one thing the screen wants you to do, "labelled with *which* of read
/// and continue will happen — so a screen-reader user learns the outcome before taking it
/// rather than after". An audiobook is a third and a fourth answer, because *Read* is not what
/// the button does: `open(_:at:)` sends an audiobook to the player, and it always did — the
/// wording was the only thing that never followed.
///
/// A value with a test rather than a ternary in a view body, for the reason `PlayerLabels` is
/// one: this is a requirement, and a requirement stated inside a `Text` is a requirement
/// nothing checks.
@Suite("The publication page's primary action")
struct PrimaryActionTests {

    @Test("An unread comic or book says read")
    func unreadIsRead() {
        for format in [PublicationFormat.cbz, .epub, .pdf, .imageFolder] {
            #expect(PrimaryAction.of(format, hasProgress: false) == .read)
        }
    }

    @Test("One in progress says continue")
    func startedIsContinue() {
        #expect(PrimaryAction.of(.epub, hasProgress: true) == .continueReading)
    }

    /// Every audio format, because `local-library` makes a folder of audio one audiobook and
    /// the page cannot tell a listener a different story about an M4B, an MP3 or a folder.
    @Test("An audiobook says listen, and continue listening once it has been started")
    func audioIsListen() {
        for format in PublicationFormat.allCases.filter(\.isAudio) {
            #expect(PrimaryAction.of(format, hasProgress: false) == .listen)
            #expect(PrimaryAction.of(format, hasProgress: true) == .continueListening)
        }
    }

    /// The four answers are two questions, and neither collapses into the other: a started
    /// audiobook must not fall back to *Continue reading*, which is what a single
    /// progress-first branch would have given it.
    @Test("Reading and listening never borrow each other's words")
    func neverBorrowed() {
        let listening: Set<PrimaryAction> = [.listen, .continueListening]
        let reading: Set<PrimaryAction> = [.read, .continueReading]
        for hasProgress in [true, false] {
            #expect(listening.contains(PrimaryAction.of(.m4b, hasProgress: hasProgress)))
            #expect(reading.contains(PrimaryAction.of(.cbr, hasProgress: hasProgress)))
        }
    }

    /// A book heard to the end starts again at its first chapter, so the action names no
    /// chapter at all.
    ///
    /// `reading-progress`: "reopening a finished publication starts at the beginning while
    /// retaining the finished record", and `StoryArcApp.resumePlace(of:)` drops a finished
    /// record's stored place for that reason. The page read the same record without that
    /// guard, so the button promised *Continue "The Reach"* while the audio began at *The
    /// Harbour* — and the promise about the outcome is the one thing this value exists to
    /// keep. Android answers null here in `ListenedPosition.resume`; this is the iOS half of
    /// the same rule.
    @Test("A finished audiobook names no chapter, because it starts again at its first")
    func finishedNamesNoChapter() {
        let parts = (0..<3).map { PlaybackPart(index: $0, title: "Chapter \($0 + 1)", duration: 600) }
        let heard = ReadingProgress(
            identity: PublicationIdentity(contentDigest: "book"),
            position: .listening(part: 2, partCount: 3, offset: 30, of: 600),
            isFinished: true,
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let book = DetailChapters.of(.m4b, parts: parts, progress: heard)

        #expect(book.resuming == nil)
        #expect(PrimaryAction.of(.m4b, hasProgress: true, chapter: book.resuming) == .continueListening)
    }
}
