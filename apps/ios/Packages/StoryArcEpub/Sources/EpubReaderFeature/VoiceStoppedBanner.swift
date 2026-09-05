internal import SwiftUI

internal import DesignSystem
internal import Playback

/// Tells the reader, once, that opening this book stopped the voice on another.
///
/// `ebook-reader`, *Opening a different publication*: "the listener is told once that the voice
/// stopped, rather than discovering it by silence". The word belongs over *this* page because
/// this is where the listener is looking — at the publication they just opened, not at the one
/// that went quiet — which is also why the sentence names that other book.
///
/// **Brief, non-modal, and it leaves on its own.** Nothing waits on it and nothing is lost by
/// ignoring it: the voice is already stopped and its position already written. Six seconds,
/// the dwell this app's transient chrome has used before, and long enough to read a title.
///
/// **Announced once.** VoiceOver is told the sentence as the banner appears, so a listener who
/// cannot see the capsule is not the one listener left to discover the silence.
///
/// **Already spent by the time it is drawn.** ``EpubReaderModel`` took the notice from the
/// centre in the same run of the main actor that displaced the voice — see
/// `prepareReadAloud` — so what the model holds is the word for this dwell and nothing else,
/// and a return to this book finds the centre with nothing to say. That is what makes *once*
/// structural rather than a flag somebody remembers to clear.
///
/// Glass, like the return control and the transport it sits above, because it is a piece of the
/// reader's chrome over a page. `PlayerFeature`'s `VoiceStoppedCapsule` draws the same
/// sentence on the shell; two views because the two packages cannot share one without a new
/// dependency, and one ``VoiceStoppedNotice`` so the rule behind them cannot drift. Android
/// says it with a `Snackbar` from each surface's own scaffold.
struct VoiceStoppedBanner: View {
    /// What the notice says, from ``VoiceStoppedNotice/sentence``.
    let sentence: String
    /// Called when the dwell is up, so the model can let the word go.
    let dismiss: () -> Void

    /// How long the word stays.
    private static let dwell: Duration = .seconds(6)

    var body: some View {
        Text(sentence)
            .textRole(.footnote)
            .storyArcGlassText()
            .multilineTextAlignment(.center)
            // Wraps rather than truncates: the title is the part that matters, and at the
            // largest text size a long one needs a second line.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, StoryArcSpace.md)
            .padding(.vertical, StoryArcSpace.xs)
            .storyArcGlass()
            .padding(.horizontal, StoryArcSpace.gutter)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("voice-stopped")
            .task {
                AccessibilityNotification.Announcement(sentence).post()
                try? await Task.sleep(for: Self.dwell)
                // Cancelled means the reader left before the dwell was up. The word was on
                // screen for as long as they were, which is all that was owed.
                guard !Task.isCancelled else { return }
                dismiss()
            }
    }
}
