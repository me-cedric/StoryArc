internal import SwiftUI

internal import DesignSystem

extension ReaderView {
    /// `DesignSystem`'s banner, drawn when D18's handover left a word pending. `ReaderView.swift`
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
