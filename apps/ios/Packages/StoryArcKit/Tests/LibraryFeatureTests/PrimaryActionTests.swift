import Foundation
import Testing

@testable import LibraryFeature
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

    /// Both audio formats, because `local-library` makes a folder of audio one audiobook and
    /// the page cannot tell a listener a different story about it.
    @Test("An audiobook says listen, and continue listening once it has been started")
    func audioIsListen() {
        for format in [PublicationFormat.audiobook, .audioFolder] {
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
            #expect(listening.contains(PrimaryAction.of(.audiobook, hasProgress: hasProgress)))
            #expect(reading.contains(PrimaryAction.of(.cbr, hasProgress: hasProgress)))
        }
    }
}
