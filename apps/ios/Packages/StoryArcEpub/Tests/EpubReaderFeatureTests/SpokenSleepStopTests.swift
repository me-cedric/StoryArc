import Foundation
import Synchronization
import Testing

import ReadiumNavigator
import ReadiumShared
import StoryArcCore
@testable import EpubReaderFeature

/// D19: when the sleep timer runs out, a voice "stops at the end of the current sentence".
///
/// Driven through Readium's real synthesizer over the fixture book. Only the engine is a
/// double: it holds each sentence until the test finishes it, so the test decides where a
/// sentence ends and can see whether one was cut.
@MainActor
@Suite("A voice the sleep timer stops")
struct SpokenSleepStopTests {

    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(
                atPath: candidate.appending(path: "manifest.json").path
            ) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    /// The fixture book, open, with a synthesizer that speaks through `engine`.
    private func speaking(through engine: HeldEngine) async throws
        -> (SpokenSource, PublicationSpeechSynthesizer) {
        let url = Self.corpus.appending(path: "ebooks/fixture.epub")
        let reader = EpubReaderModel(
            publication: StoryArcCore.Publication(
                identity: PublicationIdentity(normalizedPath: url.path),
                format: .epub,
                displayTitle: "fixture.epub",
                origin: .embedded
            ),
            url: url
        )
        await reader.open()
        let opened = try #require(reader.opened)
        let speech = try #require(
            PublicationSpeechSynthesizer(publication: opened, engineFactory: engine.make)
        )
        let source = SpokenSource(speaking: speech, with: SpokenVoice(), in: opened, from: nil)
        return (source, speech)
    }

    /// Waits for `condition`, for at most five seconds.
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<250 where !condition() {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test("Running out lets the sentence being spoken finish, and the next one never starts")
    func stopsAtTheEndOfTheSentence() async throws {
        let engine = HeldEngine()
        let (source, speech) = try await speaking(through: engine)
        var sentences = 0
        source.onSentence = { _ in sentences += 1 }

        source.play()
        await until { sentences == 1 }
        try #require(sentences == 1, "the first sentence was never reported")

        source.stopAtSentenceEnd()
        try await Task.sleep(for: .milliseconds(200))
        #expect(engine.cut.isEmpty, "the sentence being spoken was cut mid-word")

        engine.finishSentence()
        await until { if case .paused = speech.state { true } else { false } }

        guard case let .paused(utterance) = speech.state else {
            Issue.record("the voice did not stop at the next sentence: \(speech.state)")
            return
        }
        #expect(engine.said.count == 2, "the voice went past the next sentence")
        #expect(utterance.text == engine.said.last, "the voice stopped somewhere else")
        #expect(engine.cut == [utterance.text], "the next sentence was not silenced as it began")
    }

    @Test("Pressing play while the stop waits keeps the voice going past the sentence end")
    func playCancelsTheWaitingStop() async throws {
        let engine = HeldEngine()
        let (source, speech) = try await speaking(through: engine)
        var sentences = 0
        source.onSentence = { _ in sentences += 1 }

        source.play()
        await until { sentences == 1 }
        try #require(sentences == 1, "the first sentence was never reported")

        source.stopAtSentenceEnd()
        source.play()
        engine.finishSentence()
        await until { sentences == 2 }

        #expect(sentences == 2, "the next sentence was never reported")
        #expect(engine.cut.isEmpty, "the voice stopped although the listener pressed play")
        guard case .playing = speech.state else {
            Issue.record("the voice stopped although the listener pressed play: \(speech.state)")
            return
        }
    }
}

/// A speech engine that holds each sentence until the test finishes it.
///
/// `@unchecked Sendable`: Readium calls it from its own task and the test reads it from the
/// main actor, and every stored value is behind the one lock. Shared with
/// `SpokenReturnTests`.
final class HeldEngine: TTSEngine, @unchecked Sendable {

    private struct Held {
        var said: [String] = []
        var cut: [String] = []
        var finishing: CheckedContinuation<Result<Void, TTSError>, Never>?
        var cancelled = false
    }

    private let state = Mutex(Held())

    var availableVoices: [TTSVoice] { [] }

    /// Every sentence the engine was asked to speak, in order.
    var said: [String] { state.withLock { $0.said } }

    /// Every sentence stopped before the test finished it.
    var cut: [String] { state.withLock { $0.cut } }

    /// For `engineFactory`: a method, not a closure, so it carries no actor isolation into
    /// Readium's task. See `SpokenVoice.makeEngine()`.
    nonisolated func make() -> any TTSEngine { self }

    /// Ends the sentence being spoken, as if the engine had said its last word.
    func finishSentence() {
        let finishing = state.withLock { held in
            defer { held.finishing = nil }
            return held.finishing
        }
        finishing?.resume(returning: .success(()))
    }

    func speak(
        _ utterance: TTSUtterance,
        onSpeakRange: @escaping (Range<String.Index>) -> Void
    ) async -> Result<Void, TTSError> {
        let text = utterance.text
        state.withLock { held in
            held.said.append(text)
            held.cancelled = false
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let cancelled = state.withLock { held in
                    if !held.cancelled { held.finishing = continuation }
                    return held.cancelled
                }
                if cancelled { continuation.resume(returning: .success(())) }
            }
        } onCancel: {
            let finishing = state.withLock { held in
                held.cut.append(text)
                held.cancelled = true
                defer { held.finishing = nil }
                return held.finishing
            }
            finishing?.resume(returning: .success(()))
        }
    }
}
