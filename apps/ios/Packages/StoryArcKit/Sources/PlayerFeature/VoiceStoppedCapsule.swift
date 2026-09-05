public import SwiftUI

internal import DesignSystem
public import Playback

public extension View {

    /// Draws the word a displaced voice owes over this view, once, whenever `centre` holds one.
    ///
    /// `ebook-reader`, *Opening a different publication*: "the listener is told once that the
    /// voice stopped, rather than discovering it by silence". This is the shell's half of that
    /// sentence. An audiobook started from the shelf presents no screen — the compact bar is the
    /// surface a listener gets, and they are looking at the shelf — so the shelf is where the
    /// word has to land. A reader that displaced a voice takes the word itself, in the same run
    /// that displaced, and this never sees it pending; see `PlayerCentre.takeVoiceStopped()`.
    func voiceStoppedNotice(from centre: PlayerCentre) -> some View {
        modifier(VoiceStoppedNoticeModifier(centre: centre))
    }
}

/// Watches the centre for a word owed, takes it, and shows it for one dwell.
private struct VoiceStoppedNoticeModifier: ViewModifier {
    let centre: PlayerCentre

    /// The word being shown, already taken from the centre.
    ///
    /// Local state because the centre's copy is spent the moment it is read — that is what
    /// makes *once* structural — so the sentence has to be held somewhere for as long as it is
    /// on screen, and the view showing it is the only thing with that lifetime.
    @State private var shown: VoiceStoppedNotice = .none

    func body(content: Content) -> some View {
        content
            // The top, not the foot. The foot is the tab bar and the dock that has just
            // started showing the *new* book; a word about the old one sitting on top of it
            // would read as a caption for the wrong thing.
            .overlay(alignment: .top) {
                if let sentence = shown.sentence {
                    VoiceStoppedCapsule(sentence: sentence) { shown = shown.taken() }
                        .padding(.top, StoryArcSpace.sm)
                        .transition(.opacity)
                }
            }
            .onChange(of: centre.voiceStopped) { _, owed in
                guard owed.isPending else { return }
                shown = centre.takeVoiceStopped()
            }
    }
}

/// The sentence itself: brief, non-modal, announced once, and gone on its own.
///
/// Nothing waits on it and nothing is lost by ignoring it: the voice is already stopped and its
/// position already written. Six seconds, the dwell this app's transient chrome has used
/// before, and long enough to read a title. VoiceOver is told the sentence as the capsule
/// appears, so a listener who cannot see it is not the one listener left to discover the
/// silence.
///
/// `EpubReaderFeature`'s `VoiceStoppedBanner` is the same view over a page; two because the two
/// packages cannot share one without a new dependency, and one ``VoiceStoppedNotice`` so the
/// rule behind them cannot drift. Android says it with a `Snackbar` from each surface's own
/// scaffold.
struct VoiceStoppedCapsule: View {
    let sentence: String
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
                // Cancelled means the view went before the dwell was up. The word was on
                // screen for as long as the listener was, which is all that was owed.
                guard !Task.isCancelled else { return }
                dismiss()
            }
    }
}
