public import SwiftUI

/// Tells the reader, once, that opening this publication stopped a voice on another book.
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
/// Glass, like the return control and the transport it sits above, because it is a piece of the
/// reader's chrome over a page. Both readers draw it; `PlayerFeature`'s `VoiceStoppedCapsule`
/// draws the same sentence on the shell, and one `VoiceStoppedNotice` in `Playback` holds the
/// rule behind all three so it cannot drift. Android says it with a `Snackbar` from each
/// surface's own scaffold.
public struct VoiceStoppedBanner: View {
    /// What the notice says, from `VoiceStoppedNotice.sentence`.
    private let sentence: String
    /// Called when the dwell is up, so the model can let the word go.
    private let dismiss: () -> Void

    /// How long the word stays.
    private static let dwell: Duration = .seconds(6)

    public init(sentence: String, dismiss: @escaping () -> Void) {
        self.sentence = sentence
        self.dismiss = dismiss
    }

    public var body: some View {
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
