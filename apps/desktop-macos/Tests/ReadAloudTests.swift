import Foundation
import Playback
import StoryArcCore
import Testing

@testable import StoryArc

/// A voice list a test chooses.
struct FakeVoices: SpeechVoices {
    let byLanguage: [String: [String]]

    func voices(for language: String?) -> [String] {
        guard let language else { return byLanguage.values.flatMap { $0 } }
        return byLanguage[language] ?? []
    }
}

/// A speaker that says every sentence at once, and remembers what it was asked to say.
@MainActor
final class FakeSpeaker: SentenceSpeaking {
    private(set) var spoken: [String] = []
    private(set) var rates: [Float] = []
    private(set) var stops = 0
    private(set) var pauses = 0
    /// Held rather than called, so a test can decide when a sentence is over.
    private(set) var pending: (@MainActor () -> Void)?

    func speak(_ text: String, voice: String?, rate: Float, volume: Float, finished: @escaping @MainActor () -> Void) {
        spoken.append(text)
        rates.append(rate)
        pending = finished
    }

    func pause() { pauses += 1 }
    func resume() {}
    func stop() { stops += 1; pending = nil }

    /// The sentence being spoken comes to its end.
    func finish() {
        let done = pending
        pending = nil
        done?()
    }
}

/// Read-aloud on the Mac: absent with no voice, the sentences of the corpus book, and a
/// voice that walks them across chapters and stops at the end. `ebook-reader`, *Reading
/// aloud*; `desktop-experience`, *A device with no speech engine*. Task 4.8.
@MainActor
@Suite("Read aloud")
struct ReadAloudTests {
    @Test("With no voice at all the control is absent; with one, it is offered for any language")
    func noVoices() {
        let none = FakeVoices(byLanguage: [:])
        #expect(!MacReadAloud.isAvailable(language: "en", voices: none))
        #expect(MacReadAloud.voice(for: "en", voices: none) == nil)
        let french = FakeVoices(byLanguage: ["fr": ["com.apple.voice.fr.Thomas"]])
        #expect(MacReadAloud.isAvailable(language: "en", voices: french))
        #expect(MacReadAloud.voice(for: "fr", voices: french) == "com.apple.voice.fr.Thomas")
        #expect(MacReadAloud.voice(for: "en", voices: french) == "com.apple.voice.fr.Thomas", "any voice over none")
    }

    @Test("The EPUB window offers the control only where a voice exists and the book has text")
    func controlFollowsAvailability() async throws {
        let chapters = try await SpokenChapters.read(url: TestFixtures.ebooks.appending(path: "fixture.epub"))
        #expect(chapters.hasSomethingToSay)
        #expect(EpubReaderModel.offersReadAloud(chapters: chapters, voices: FakeVoices(byLanguage: [:])) == false)
        let voices = FakeVoices(byLanguage: ["en": ["com.apple.voice.en.Samantha"]])
        #expect(EpubReaderModel.offersReadAloud(chapters: chapters, voices: voices))
        let silent = SpokenChapters(chapters: [.init(href: "a.xhtml", title: nil, sentences: [])], language: "en")
        #expect(!silent.hasSomethingToSay)
        #expect(EpubReaderModel.offersReadAloud(chapters: silent, voices: voices) == false)
    }

    @Test("The corpus fixture's chapters come out as titled parts of sentences")
    func chapters() async throws {
        let chapters = try await SpokenChapters.read(url: TestFixtures.ebooks.appending(path: "fixture.epub"))
        #expect(chapters.chapters.map(\.href) == ["OEBPS/ch1.xhtml", "OEBPS/ch2.xhtml"])
        #expect(chapters.parts.map(\.title) == ["Chapter One", "Chapter Two"])
        #expect(chapters.parts.allSatisfy { $0.duration == nil })
        #expect(chapters.language == "en")
        let first = try #require(chapters.chapters.first)
        #expect(first.sentences.first == "Chapter One")
        #expect(first.sentences.count > 10)
        #expect(first.sentences.allSatisfy { !$0.contains("<") })
        let one = try await SpokenChapters.read(url: TestFixtures.ebooks.appending(path: "one-sentence.epub"))
        #expect(one.chapters.flatMap(\.sentences).count <= 2)
    }

    @Test("Sentences split on their ends and on paragraphs, and markup becomes text")
    func splitter() {
        #expect(SentenceSplitter.sentences(in: "One. Two! Three? Four") == ["One.", "Two!", "Three?", "Four"])
        let paragraphs = SentenceSplitter.sentences(in: "A heading\nA paragraph. Another.")
        #expect(paragraphs == ["A heading", "A paragraph.", "Another."])
        #expect(SentenceSplitter.sentences(in: "  \n ") == [])
        let text = SentenceSplitter.text(ofMarkup: "<html><head><title>x</title></head><body><h1>Hi &amp; bye</h1>"
            + "<p>One  two.</p><script>bad()</script><p>Three.</p></body></html>")
        #expect(text == "Hi & bye\nOne two.\nThree.")
    }

    @Test("The voice walks the sentences across the chapter boundary, skips by one, and ends with the book")
    func walksAndEnds() {
        let chapters = SpokenChapters(chapters: [
            .init(href: "a", title: "A", sentences: ["A one.", "A two."]),
            .init(href: "b", title: "B", sentences: ["B one."]),
        ], language: "en")
        let speaker = FakeSpeaker()
        let source = MacSpokenSource(chapters: chapters, speaker: speaker, voice: "v")
        var moves = 0
        var ended = 0
        var sentences: [String?] = []
        source.moved = { moves += 1 }
        source.ended = { ended += 1 }
        source.onSentence = { sentences.append($0) }
        source.setSpeed(PlaybackSpeed(1.5))

        source.play()
        #expect(speaker.spoken == ["A one."])
        #expect(speaker.rates.first == SpeechRate.avRate(for: PlaybackSpeed(1.5)))
        speaker.finish()
        #expect(speaker.spoken == ["A one.", "A two."] && source.place == PlaybackPlace(partIndex: 0, offset: 1))
        speaker.finish()
        #expect(source.place == PlaybackPlace(partIndex: 1, offset: 0), "the voice carries on into the next chapter")
        #expect(speaker.spoken.last == "B one.")
        source.skip(.back, by: 0)
        #expect(source.place == PlaybackPlace(partIndex: 0, offset: 1) && speaker.spoken.last == "A two.")
        source.skip(.forward, by: 0)
        source.pause()
        #expect(speaker.pauses == 1)
        source.play()
        speaker.finish()
        #expect(ended == 1, "the end of the last sentence ends the book")
        // The highlight is withdrawn at the end: the last sentence reported is none.
        #expect(!sentences.isEmpty && sentences.last.flatMap { $0 } == nil)
        #expect(moves >= 4)
        #expect(source.neighbour(of: PlaybackPlace(partIndex: 1, offset: 0), .forward) == nil)
        source.stop()
        #expect(speaker.stops >= 1)
    }
}
