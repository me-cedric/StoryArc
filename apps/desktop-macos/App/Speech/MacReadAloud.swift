import AVFoundation
import Formats
import Foundation
import Playback
import StoryArcCore

/// The voices the system offers, as read-aloud asks about them. The system's own in the app,
/// a list in the tests, so *A device with no speech engine* can be measured.
protocol SpeechVoices: Sendable {
    /// The identifiers of the voices that can speak this language, or any language for `nil`.
    func voices(for language: String?) -> [String]
}

struct SystemSpeechVoices: SpeechVoices {
    func voices(for language: String?) -> [String] {
        let all = AVSpeechSynthesisVoice.speechVoices()
        guard let language else { return all.map(\.identifier) }
        let wanted = language.lowercased().split(separator: "-").first.map(String.init) ?? language.lowercased()
        return all.filter { $0.language.lowercased().hasPrefix(wanted) }.map(\.identifier)
    }
}

/// Whether read-aloud is offered at all. `desktop-experience`, *A device with no speech
/// engine*: where the system offers no voice the control is absent and nothing says it
/// failed. A book in a language no installed voice speaks falls back to any voice, as the
/// iOS reader lets Readium do; only a system with no voice at all has no control.
@MainActor
enum MacReadAloud {
    static var voices: any SpeechVoices = SystemSpeechVoices()

    static func isAvailable(language: String?, voices: any SpeechVoices = voices) -> Bool {
        !voices.voices(for: nil).isEmpty
    }

    /// The voice to speak a language with: one of the language's own, else any.
    static func voice(for language: String?, voices: any SpeechVoices = voices) -> String? {
        voices.voices(for: language).first ?? voices.voices(for: nil).first
    }
}

/// Sentences out of a chapter's text, in the publication's own order.
///
/// A plain splitter rather than Readium's tokenizer, which the Mac has no Swift copy of: the
/// end of a sentence is a full stop, a question mark or an exclamation mark followed by
/// space or the end, and a heading or a paragraph break ends one too. Task 4.8.
enum SentenceSplitter {
    static func sentences(in text: String) -> [String] {
        var found: [String] = []
        for block in text.components(separatedBy: "\n") {
            var current = ""
            for character in block {
                current.append(character)
                if ".!?…".contains(character) {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { found.append(trimmed) }
                    current = ""
                }
            }
            let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { found.append(rest) }
        }
        return found
    }

    /// The readable text of XHTML: scripts and styles dropped, block ends as line breaks,
    /// entities undone, whitespace folded.
    static func text(ofMarkup markup: String) -> String {
        var cleaned = markup
        for tag in ["script", "style", "head"] {
            cleaned = cleaned.replacingOccurrences(
                of: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive]
            )
        }
        cleaned = cleaned.replacingOccurrences(
            of: "</?(p|div|h[1-6]|li|br|tr|section|article|blockquote|aside|figcaption|dd|dt)[^>]*>",
            with: "\n", options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        cleaned = cleaned
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
        return cleaned
            .components(separatedBy: "\n")
            .map { $0.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\r" }).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

/// What a reflowable book says, chapter by chapter: the reading order's text as sentences.
struct SpokenChapters: Sendable, Equatable {
    struct Chapter: Sendable, Equatable {
        let href: String
        let title: String?
        let sentences: [String]
    }

    let chapters: [Chapter]
    let language: String?

    /// Whether there is anything to say: *A publication with nothing to say* has no control.
    var hasSomethingToSay: Bool { chapters.contains { !$0.sentences.isEmpty } }

    var parts: [PlaybackPart] {
        SpokenParts.of(
            readingOrder: chapters.map(\.href),
            titledBy: Dictionary(chapters.compactMap { chapter in chapter.title.map { (chapter.href, $0) } },
                                 uniquingKeysWith: { first, _ in first })
        )
    }

    /// Reads every chapter of the EPUB at `url`.
    static func read(url: URL) async throws -> SpokenChapters {
        let reader = try await EpubReader(source: try FileSource(url: url))
        let titles = Dictionary(reader.toc.map { ($0.href, $0.title) }, uniquingKeysWith: { first, _ in first })
        var chapters: [Chapter] = []
        for item in reader.spine {
            let data = (try? await reader.data(at: item.href)) ?? Data()
            let markup = String(data: data, encoding: .utf8) ?? ""
            chapters.append(Chapter(
                href: item.href, title: titles[item.href],
                sentences: SentenceSplitter.sentences(in: SentenceSplitter.text(ofMarkup: markup))
            ))
        }
        return SpokenChapters(chapters: chapters, language: reader.metadata.language)
    }
}
