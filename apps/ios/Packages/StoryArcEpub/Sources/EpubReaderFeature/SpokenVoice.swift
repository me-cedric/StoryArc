internal import Foundation
internal import Synchronization

internal import AVFoundation

internal import ReadiumNavigator

internal import Playback

/// The one thing Readium leaves to the caller: how fast the voice speaks.
///
/// **This is an extension point, not a workaround.** `PublicationSpeechSynthesizer.
/// Configuration` at 3.11.0 carries a language and a voice and no rate, and
/// `AVTTSEngine.swift:131` — `utter.rate = rateMultiplierToAVRate(...)` — is commented out
/// upstream. Two lines below it the same method calls
/// `delegate?.avTTSEngine(self, didCreateUtterance:)`, whose own doc comment reads *"You can
/// customize additional properties of the utterance."* Upstream deleted the property and
/// kept the hook: the caller sets this now.
///
/// So this is the delegate, and `PublicationSpeechSynthesizer.init(engineFactory:)` — public,
/// defaulting to `{ AVTTSEngine() }` — is where it is injected. Readium's tokenisation, its
/// locators and its highlight mapping are all untouched, which is the whole reason not to
/// fork or to reimplement: they are the hard part and they already work.
///
/// **It outlives the reader.** `AVTTSEngine` holds its delegate weakly, so one owned by a
/// screen would be deallocated the moment the screen was and every utterance after that
/// would speak at the platform default. ``SpokenSource`` owns it for the life of the
/// session, and ``EpubReaderModel`` owns it until one begins.
///
/// **A change applies to the next sentence, not the current one.** The rate is a property of
/// an `AVSpeechUtterance` and an utterance already being spoken cannot be re-rated. Readium
/// says the same of its own configuration — *"Changes are not immediate, they will be
/// applied for the next utterance"* — and the alternative, restarting the sentence at the
/// new speed, would repeat words the listener has already heard to save them a second.
///
/// **`Mutex` rather than isolation.** `AVTTSEngineDelegate` carries no isolation, and
/// `AVTTSEngine` is a plain `NSObject`, so the compiler cannot be told this is only ever
/// reached from the main actor — which in practice it is, from `AVTTSEngine.speak`. A lock
/// costs nothing once per sentence and is the honest answer to a callback whose isolation
/// upstream does not state.
final class SpokenVoice: NSObject, AVTTSEngineDelegate, Sendable {

    private let rate = Mutex<Float>(SpeechRate.avRate(for: .normal))

    /// The speed every utterance from here on is spoken at.
    func speak(at speed: PlaybackSpeed) {
        rate.withLock { $0 = SpeechRate.avRate(for: speed) }
    }

    func avTTSEngine(_ engine: AVTTSEngine, didCreateUtterance utterance: AVSpeechUtterance) {
        utterance.rate = rate.withLock { $0 }
    }
}
