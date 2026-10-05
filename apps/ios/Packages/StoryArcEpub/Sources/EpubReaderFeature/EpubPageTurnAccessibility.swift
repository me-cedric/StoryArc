internal import SwiftUI

internal import StoryArcCore

/// The reading position as one sentence, for the menu and for a screen reader alike.
///
/// `ebook-reader` states a reflowable position "in words, in one line", and this is that line:
/// three localised fragments joined by punctuation, because the chapter's own title is the
/// publication's and must not be translated. A position said one way on the menu and another
/// way out loud is two positions, so ``EpubReaderView/progressText`` asks this too.
///
/// Free of the view so a host test can read it without a simulator: `StoryArcEpub` needs one
/// to build at all, and the sentence is the part `StoryArcKit`'s own suite can hold to.
func epubPositionSentence(_ position: ReadingPositionLine) -> String {
    let through = String(
        localized: "epub.progress \(position.percentThrough)",
        bundle: .module,
        locale: .storyArc
    )
    guard let chapter = position.chapter else { return through }
    guard let remainder = position.chapterRemainder else { return "\(through) · \(chapter)" }
    let left = String(
        localized: String.LocalizationValue(remainder.titleKey),
        bundle: .module,
        locale: .storyArc
    )
    return "\(through) · \(chapter), \(left)"
}

/// A named page turn, and the position the turn arrived at.
///
/// `native-experience`, *Screen reader*: "the reader announces the page number and total on
/// each turn, and offers gestures to turn pages". Neither held here. The page is a web view,
/// so VoiceOver moved through its paragraphs and was offered nothing that turned a page, and
/// no turn — by a tap zone, an arrow key, a game controller, a swipe, or Fast fade — said
/// afterwards where the reader had arrived.
///
/// **The announcement hangs off the position, not off each turn site.** A path nobody wired
/// would give a silence indistinguishable from the rest working, so this reads where the
/// reader is rather than what moved them.
///
/// It watches ``ReflowablePosition``, not the sentence alone. The sentence names a whole
/// percentage, and one page of a long book moves the position without moving that number — so
/// a reader turning through a chapter would be told nothing until the percentage happened to
/// tick over. The comic reader's equivalent can watch its own sentence, because a page number
/// changes on every turn (`PageTurnAccessibility.swift`).
struct EpubPageTurnAccessibility: ViewModifier {
    let position: ReflowablePosition
    let onTurn: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: Text("reader.turn.next", bundle: .module)) { onTurn(true) }
            .accessibilityAction(named: Text("reader.turn.previous", bundle: .module)) { onTurn(false) }
            .onChange(of: position) { _, arrived in
                AccessibilityNotification.Announcement(arrived.sentence).post()
            }
    }
}

/// Where the reader is, and the sentence that says so.
///
/// One value rather than two, so what is announced is read off the change that triggered the
/// announcement. `progression` is what makes every turn a change; `sentence` is what is said.
struct ReflowablePosition: Equatable {
    /// How far through the publication, 0…1. Moves on every turn, whatever made it.
    let progression: Double
    let sentence: String
}
