internal import SwiftUI

internal import DesignSystem
internal import Playback

/// Tells the reader, once, that opening this comic or PDF stopped a voice on another book.
///
/// D18. `ebook-reader`, *Opening a different publication*: "the listener is told once that the
/// voice stopped, rather than discovering it by silence". The word belongs over *this* page
/// because this is where the listener is looking, which is also why the sentence names the
/// book that went quiet.
///
/// **Brief, non-modal, and it leaves on its own.** Nothing waits on it and nothing is lost by
/// ignoring it: the voice is already stopped and its position already written. Six seconds,
/// the dwell this app's transient chrome has used before.
///
/// `PlayerFeature`'s `VoiceStoppedCapsule` draws the same sentence on the shell, and
/// `EpubReaderFeature`'s `VoiceStoppedBanner` draws it over a reflowable page; this is the
/// third because the three packages cannot share one view without a dependency each of them
/// would otherwise not need, and one ``VoiceStoppedNotice`` so the rule behind all three
/// cannot drift.
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
                guard !Task.isCancelled else { return }
                dismiss()
            }
    }
}

extension ReaderView {
    /// The banner above, drawn when D18's handover left a word pending. `ReaderView.swift`
    /// is at its own line cap, so this — like ``returnOffer`` in `ReaderSlider.swift` — lives
    /// beside what it draws rather than inside the view's own body.
    @ViewBuilder
    var voiceStoppedOverlay: some View {
        if let sentence = model.voiceStopped.sentence {
            VoiceStoppedBanner(sentence: sentence) { model.voiceStopped = model.voiceStopped.taken() }
                .padding(.top, StoryArcSpace.sm)
        }
    }
}
