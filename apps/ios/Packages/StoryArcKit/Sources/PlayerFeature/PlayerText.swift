public import SwiftUI

public import Playback

/// The player's decisions, said out loud.
///
/// ``PlayerLabels`` decides *what* to state and this turns each decision into words. The
/// split is not ceremony: `scripts/ios-strings.mjs` proves every key resolves in all four
/// languages by reading `Text("…")` out of the source, so the keys have to be literals in a
/// view file — and `swift build` never compiles an `.xcstrings`, so a host test can assert
/// the decision and not the prose. Each half is checked by the gate that can see it.
enum PlayerText {

    /// "15 seconds back", or "Previous sentence".
    static func skip(_ label: SkipLabel, _ direction: SkipDirection) -> Text {
        switch (label, direction) {
        case (.sentence, .back):
            Text("player.skip.sentence.previous", bundle: .module)
        case (.sentence, .forward):
            Text("player.skip.sentence.next", bundle: .module)
        case let (.time(interval), .back):
            Text("player.skip.back \(interval)", bundle: .module)
        case let (.time(interval), .forward):
            Text("player.skip.forward \(interval)", bundle: .module)
        }
    }

    /// "Part 2 of 12", or nothing at all.
    @ViewBuilder static func position(_ label: PositionLabel) -> some View {
        switch label {
        case let .time(elapsed, total):
            // Not used by the surfaces — a source with a duration draws the scrubber and its
            // two ends instead — and stated here so the type is complete rather than
            // silently partial.
            Text(verbatim: "\(elapsed) / \(total)")
        case let .part(index, count):
            Text("player.part.of \(index) \(count)", bundle: .module)
        case .none:
            EmptyView()
        }
    }

    /// A chapter's name, or its number when the container gave it none.
    static func chapter(_ label: ChapterLabel) -> Text {
        switch label {
        case let .title(title): Text(title)
        case let .number(number): Text("player.part.number \(number)", bundle: .module)
        }
    }

    /// What could not be played, or nothing for a whole book.
    ///
    /// Two keys rather than one plural: a plural variation in an `.xcstrings` carries no
    /// `stringUnit`, and `scripts/ios-strings.mjs` reads exactly that to prove every
    /// language has an answer. A string the gate cannot see is a string that can go missing.
    @ViewBuilder static func damage(unreadableParts count: Int) -> some View {
        switch count {
        case ..<1: EmptyView()
        case 1: Text("player.damaged.one", bundle: .module)
        default: Text("player.damaged.many \(count)", bundle: .module)
        }
    }
}
