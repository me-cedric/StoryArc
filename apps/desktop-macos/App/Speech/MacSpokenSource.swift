import AVFoundation
import Foundation
import Playback

/// The engine a spoken source speaks through. `AVSpeechSynthesizer` in the app; a fake in
/// the tests says each sentence finished at once.
@MainActor
protocol SentenceSpeaking: AnyObject {
    /// Speaks one sentence and calls `finished` when it has been said to the end, or not at
    /// all when it was stopped.
    func speak(_ text: String, voice: String?, rate: Float, volume: Float, finished: @escaping @MainActor () -> Void)
    func pause()
    func resume()
    func stop()
}

/// The synthesised voice as one of the player's two sources, on the Mac.
///
/// A port of `StoryArcEpub`'s `SpokenSource` without Readium: the chapters come from
/// `SpokenChapters`, a sentence at a time, and the place is the chapter and the sentence
/// within it. The two places the sources differ stay data: the parts carry no duration, and
/// the skip is a sentence. `ebook-reader`, *Reaching the end of a chapter*: the voice carries
/// on into the next chapter and stops, withdrawn, at the end of the book. Task 4.8.
@MainActor
final class MacSpokenSource: PlaybackSource {
    var moved: (@MainActor () -> Void)?
    var ended: (@MainActor () -> Void)?
    let parts: [PlaybackPart]
    private(set) var place: PlaybackPlace
    let skipUnit: SkipUnit = .sentence
    let unreadablePartCount = 0
    /// The sentence being spoken, for the window to show.
    var onSentence: (@MainActor (String?) -> Void)?

    private let chapters: SpokenChapters
    private let speaker: any SentenceSpeaking
    private let voice: String?
    private var rate = SpeechRate.avRate(for: .normal)
    private var volume: Float = 1
    private var isPlaying = false
    private var isPaused = false
    private var stoppingAtSentenceEnd = false
    /// Which utterance is current, so a sentence that finished after a skip does not advance.
    private var generation = 0

    init(chapters: SpokenChapters, speaker: any SentenceSpeaking, voice: String?, from place: PlaybackPlace = .start) {
        self.chapters = chapters
        self.speaker = speaker
        self.voice = voice
        parts = chapters.parts
        self.place = place
    }

    var currentSentence: String? {
        guard chapters.chapters.indices.contains(place.partIndex) else { return nil }
        let sentences = chapters.chapters[place.partIndex].sentences
        let index = Int(place.offset)
        return sentences.indices.contains(index) ? sentences[index] : nil
    }

    func play() {
        if isPaused {
            isPaused = false
            isPlaying = true
            speaker.resume()
            return
        }
        guard !isPlaying else { return }
        isPlaying = true
        speakCurrent()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        isPaused = true
        speaker.pause()
    }

    func stop() {
        isPlaying = false
        isPaused = false
        generation += 1
        speaker.stop()
        onSentence?(nil)
    }

    func setSpeed(_ speed: PlaybackSpeed) { rate = SpeechRate.avRate(for: speed) }

    func setVolume(_ gain: Double) { volume = Float(min(1, max(0, gain))) }

    func stopAtSentenceEnd() { stoppingAtSentenceEnd = true }

    func seek(toPart index: Int, offset: TimeInterval) {
        move(to: PlaybackPlace(partIndex: index, offset: offset))
    }

    func skip(_ direction: SkipDirection, by interval: TimeInterval) {
        guard let next = neighbour(of: place, direction) else { return }
        move(to: next)
    }

    // MARK: - The sentences

    private func move(to next: PlaybackPlace) {
        generation += 1
        speaker.stop()
        isPaused = false
        place = next
        moved?()
        if isPlaying { speakCurrent() }
    }

    private func speakCurrent() {
        guard let sentence = currentSentence else {
            // Past the last sentence of the last chapter: the end of the book.
            isPlaying = false
            onSentence?(nil)
            ended?()
            return
        }
        generation += 1
        let mine = generation
        onSentence?(sentence)
        speaker.speak(sentence, voice: voice, rate: rate, volume: volume) { [weak self] in
            guard let self, mine == generation else { return }
            finishedSentence()
        }
    }

    private func finishedSentence() {
        if stoppingAtSentenceEnd {
            stoppingAtSentenceEnd = false
            isPlaying = false
            isPaused = true
            moved?()
            return
        }
        guard let next = neighbour(of: place, .forward) else {
            isPlaying = false
            onSentence?(nil)
            ended?()
            return
        }
        place = next
        moved?()
        speakCurrent()
    }

    /// The next or previous sentence, across chapter boundaries; `nil` past either end.
    func neighbour(of place: PlaybackPlace, _ direction: SkipDirection) -> PlaybackPlace? {
        let list = chapters.chapters
        var part = place.partIndex
        var sentence = Int(place.offset) + (direction == .forward ? 1 : -1)
        while list.indices.contains(part) {
            if list[part].sentences.indices.contains(sentence) {
                return PlaybackPlace(partIndex: part, offset: TimeInterval(sentence))
            }
            part += direction == .forward ? 1 : -1
            guard list.indices.contains(part) else { return nil }
            sentence = direction == .forward ? 0 : list[part].sentences.count - 1
        }
        return nil
    }
}

/// `AVSpeechSynthesizer`, one utterance at a time.
@MainActor
final class SystemSentenceSpeaker: NSObject, SentenceSpeaking, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var finished: (@MainActor () -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, voice: String?, rate: Float, volume: Float, finished: @escaping @MainActor () -> Void) {
        self.finished = finished
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.volume = volume
        if let voice { utterance.voice = AVSpeechSynthesisVoice(identifier: voice) }
        synthesizer.speak(utterance)
    }

    func pause() { synthesizer.pauseSpeaking(at: .word) }

    func resume() { synthesizer.continueSpeaking() }

    func stop() {
        finished = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let done = finished
            finished = nil
            done?()
        }
    }
}
