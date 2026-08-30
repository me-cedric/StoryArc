internal import SwiftUI

internal import DesignSystem

/// The transport, on screen only while a book is being read aloud.
///
/// Four controls and no scrubber. `ebook-reader` asks the *lock screen* for "play, pause,
/// and sentence skip", and the reader looking at the page gets the same four plus a stop —
/// because the way out of speech is not obvious from a pause button, and a reader who is
/// done listening should not have to guess.
///
/// It appears where the return control does, above the percentage, and for the same
/// reason: it comes and goes, and a control that appeared among the ones at the top would
/// move them.
///
/// Four glass buttons and no glass behind them. The first version put the row on a
/// `storyArcGlass()` surface and the four on top of it, and on a simulator three of the
/// four glyphs vanished: glass over glass lightens twice, and a tinted symbol on the
/// result is not a symbol any more. These sit directly in the chrome's own
/// `GlassEffectContainer`, exactly as the four at the top of the screen do.
///
/// Android's `ReadAloudBar` is the same five decisions in Compose.
struct ReadAloudBar: View {
    @Environment(\.theme) private var theme

    let isSpeaking: Bool
    let onPrevious: () -> Void
    let onToggle: () -> Void
    let onNext: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: StoryArcSpace.sm) {
            control("backward.end", "readaloud.previous", action: onPrevious)
            control(
                isSpeaking ? "pause.fill" : "play.fill",
                isSpeaking ? "readaloud.pause" : "readaloud.play",
                tint: theme.accent,
                action: onToggle
            )
            control("forward.end", "readaloud.next", action: onNext)
            control("stop.fill", "readaloud.stop", action: onStop)
        }
    }

    private func control(
        _ symbol: String,
        _ label: LocalizedStringKey,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(label, bundle: .module)
            } icon: {
                Image(systemName: symbol)
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.glass)
        .tint(tint ?? theme.palette.textPrimary)
    }
}
