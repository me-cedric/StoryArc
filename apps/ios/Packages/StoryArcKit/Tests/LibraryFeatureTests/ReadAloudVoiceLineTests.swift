import Testing

@testable import LibraryFeature
import StoryArcCore

/// Task 16.7 / D38: a publication page names the device's own read-aloud voice, or says that
/// none reads the book's language. Pure, exactly because ``ReadAloudVoiceLookup`` — the one
/// call to `AVSpeechSynthesisVoice` this feature makes — is not: what voices a test runner
/// happens to have installed is not this suite's to depend on, so every fact arrives already
/// resolved.
@Suite("Read-aloud voice line")
struct ReadAloudVoiceLineTests {

    @Test("A narrated or image format names no voice, whatever the language")
    func onlyEpubNamesAVoice() {
        for format in PublicationFormat.allCases where format != .epub {
            #expect(
                ReadAloudVoiceLine.fact(format: format, languageCode: "en", voiceName: "Ava")
                    == nil
            )
        }
    }

    @Test("An EPUB with no stated language names no voice either")
    func noLanguageIsNoFact() {
        #expect(ReadAloudVoiceLine.fact(format: .epub, languageCode: nil, voiceName: "Ava") == nil)
        #expect(ReadAloudVoiceLine.fact(format: .epub, languageCode: "", voiceName: "Ava") == nil)
    }

    @Test("An EPUB the device can speak names the voice")
    func namedVoice() {
        #expect(
            ReadAloudVoiceLine.fact(format: .epub, languageCode: "fr", voiceName: "Amélie")
                == .named("Amélie")
        )
    }

    @Test("An EPUB with no installed voice names the language instead")
    func missingVoiceNamesTheLanguage() {
        #expect(
            ReadAloudVoiceLine.fact(format: .epub, languageCode: "de", voiceName: nil)
                == .missing(InterfaceLanguage.name(of: "de"))
        )
    }
}
