internal import SwiftUI

internal import DesignSystem

extension EpubReaderView {
    /// What is over the page and is not the chrome.
    ///
    /// **Why these two are not a third revealed control.** `comic-reader`'s count is about
    /// what a centre tap reveals. The return offer is armed by a long jump the reader just
    /// made and disarmed by taking it; the transport exists only while a voice is speaking,
    /// and `read-aloud` requires it to be reachable while the reader is looking at the page.
    /// Neither arrives with the chrome and neither survives the thing that armed it.
    var transientOverlays: some View {
        VStack {
            Spacer()

            // The word owed for a voice this book's opening stopped — above the return offer,
            // because it is about what just happened somewhere else, and it leaves on its own.
            // `ebook-reader`: told once. See ``VoiceStoppedBanner``.
            if let sentence = model.voiceStopped.sentence {
                VoiceStoppedBanner(sentence: sentence) { model.voiceStopped = model.voiceStopped.taken() }
                    .padding(.bottom, StoryArcSpace.sm)
            }

            // Offered after any long jump, taken once, and never re-armed by its own use —
            // see ``EpubReaderModel/returnToWhereTheyWere()``. Above the transport because it
            // is about where the reader just was, and the transport is about what the voice
            // is doing now.
            if model.returnPoint != nil {
                ReturnControl { Task { await model.returnToWhereTheyWere() } }
                    .padding(.bottom, StoryArcSpace.sm)
            }

            if model.readAloud.isActive {
                ReadAloudBar(
                    isSpeaking: model.readAloud.isPlaying,
                    onPrevious: { model.skipSentence(forward: false) },
                    onToggle: { model.toggleReadAloud() },
                    onNext: { model.skipSentence(forward: true) },
                    onStop: { model.stopReadAloud() }
                )
                .padding(.bottom, StoryArcSpace.lg)
            }
        }
        .transition(.opacity)
    }
}
