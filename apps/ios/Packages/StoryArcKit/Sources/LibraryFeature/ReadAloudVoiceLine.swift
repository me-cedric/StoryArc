internal import SwiftUI

internal import AVFoundation

internal import DesignSystem
internal import StoryArcCore

/// What the publication page says about the device's own read-aloud voice, or nothing.
///
/// Task 16.7 / D38, `audio-playback`: "No publication page names the synthesised voice" — a
/// reader opening a book StoryArc can read aloud had no way to know, before starting, whether
/// the device had a voice for it at all. D38 settles the exact wording: *"Read aloud by %@"*
/// naming the voice, or, with none installed for the language, *"No voice on this device
/// reads %@"* naming the language instead.
///
/// EPUB is the one format this decides for: a narrated audiobook already carries a human
/// voice and nothing else in this app has text to speak at all.
enum ReadAloudVoiceFact: Equatable {
    /// The device's own voice for the publication's language, by name.
    case named(String)
    /// No installed voice reads this language, named in itself — `InterfaceLanguage.name(of:)`,
    /// the same naming every language picker in this app already uses.
    case missing(String)
}

enum ReadAloudVoiceLine {
    /// Pure: decided from facts the caller already resolved, so it needs no window and no
    /// installed voice to test against. `voiceName` is what ``ReadAloudVoiceLookup`` found —
    /// the one call in this feature that touches `AVFoundation`, and the only part a test
    /// cannot reach without a simulator's own installed voices.
    ///
    /// - Returns: `nil` for every format but EPUB, and for an EPUB with no stated language —
    ///   there is nothing to look a voice up *for*.
    static func fact(
        format: PublicationFormat,
        languageCode: String?,
        voiceName: String?
    ) -> ReadAloudVoiceFact? {
        guard format == .epub, let languageCode, !languageCode.isEmpty else { return nil }
        if let voiceName { return .named(voiceName) }
        return .missing(InterfaceLanguage.name(of: languageCode))
    }
}

/// The one call to `AVSpeechSynthesisVoice` this feature makes.
///
/// A free function rather than inlined into the view: ``ReadAloudVoiceLine/fact`` is pure
/// exactly because this lookup is not, and keeping the impure half to one line makes the
/// boundary a fact about the file rather than a convention a reviewer has to remember.
enum ReadAloudVoiceLookup {
    /// The name of the device's own voice for a language, or `nil` when none is installed.
    ///
    /// `AVSpeechSynthesisVoice(language:)` takes a bare language tag ("fr") as readily as a
    /// full one ("fr-FR") and returns the platform's own default voice for it — the same
    /// lookup `EpubReadAloud` leaves to Readium's `PublicationSpeechSynthesizer` once playback
    /// actually starts. This asks the identical question earlier, before a reader has
    /// committed to opening the book.
    static func voiceName(forLanguageCode code: String) -> String? {
        AVSpeechSynthesisVoice(language: code)?.name
    }
}

/// The line itself, drawn where ``DetailMainColumn`` puts it.
struct ReadAloudVoiceLineView: View {
    @Environment(\.theme) private var theme

    let publication: Publication

    var body: some View {
        if let fact {
            Text(text(for: fact))
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var fact: ReadAloudVoiceFact? {
        ReadAloudVoiceLine.fact(
            format: publication.format,
            languageCode: publication.language,
            voiceName: publication.language.flatMap(ReadAloudVoiceLookup.voiceName(forLanguageCode:))
        )
    }

    private func text(for fact: ReadAloudVoiceFact) -> String {
        switch fact {
        case let .named(voice):
            String(localized: "detail.readAloud.voice \(voice)", bundle: .module, locale: .storyArc)
        case let .missing(language):
            String(localized: "detail.readAloud.noVoice \(language)", bundle: .module, locale: .storyArc)
        }
    }
}
