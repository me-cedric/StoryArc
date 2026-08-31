internal import SwiftUI

/// One verb of reading aloud: its glyph, and the word a screen reader says for it.
///
/// StoryArc draws the same session on two surfaces — ``ReadAloudBar`` inside the reader and
/// ``ReadAloudDock`` in the shell's accessory slot — and they are deliberately not one
/// view. The bar sits in the reader's own `GlassEffectContainer` and uses `.glass` buttons;
/// the dock sits inside a slot the system has already made glass, and must not. That is a
/// real difference in the one property a shared view would have to fake.
///
/// What they must never disagree about is what the buttons *mean*, which is this: five
/// symbols and five keys in one place, so a renamed key or a sixth control cannot land on
/// one surface and miss the other. It is the drift a pair of near-identical transports
/// would otherwise produce, held where a compiler can see it.
///
/// The keys are the `readaloud.*` this module's catalogue already carries in four
/// languages. Nothing here adds a string.
enum ReadAloudControl: Equatable {
    case previous
    case play
    case pause
    case next
    case stop

    /// The one button whose verb depends on what the voice is doing.
    static func toggle(isSpeaking: Bool) -> ReadAloudControl { isSpeaking ? .pause : .play }

    var symbol: String {
        switch self {
        case .previous: "backward.end"
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .next: "forward.end"
        case .stop: "stop.fill"
        }
    }

    /// What a screen reader says. It is the only label these carry — they are glyphs, and a
    /// transport of unlabelled glyphs is exactly the defect the Android accessibility gate
    /// exists to catch on the other side.
    var label: LocalizedStringKey {
        switch self {
        case .previous: "readaloud.previous"
        case .play: "readaloud.play"
        case .pause: "readaloud.pause"
        case .next: "readaloud.next"
        case .stop: "readaloud.stop"
        }
    }
}
