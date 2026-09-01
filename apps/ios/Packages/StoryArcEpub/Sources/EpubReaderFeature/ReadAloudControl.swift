internal import SwiftUI

/// One verb of reading aloud: its glyph, and the word a screen reader says for it.
///
/// StoryArc drew the same session on two surfaces — ``ReadAloudBar`` inside the reader and a
/// dock of its own in the shell's accessory slot — and they were deliberately not one view:
/// the bar sits in the reader's own `GlassEffectContainer` and uses `.glass` buttons, and the
/// slot is glass the system has already made.
///
/// **The second one is gone.** `audiobooks-and-playback` puts one session behind everything
/// that speaks, so the shell's slot carries `PlayerDock` for a narrated audiobook and a
/// synthesised voice alike, with its own words. What is left here is the reader's own bar,
/// and this is still the one place its five verbs are spelled — a sixth control or a renamed
/// key lands where a compiler can see it rather than in a view body.
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
