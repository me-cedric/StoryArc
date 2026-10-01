import Foundation
import Testing

import StoryArcCore
@testable import Catalogue
@testable import LibraryFeature

/// Task 15.2: a malformed feed's parser reason, and a transport failure's raw exception
/// message, must never reach the reader. Both are logged instead of drawn.
///
/// `@MainActor` because each case moves `InterfaceLanguage`, which is one value for the whole
/// process: `ChosenLanguageFormattingTests` explains why the main actor is the only fence.
@MainActor
@Suite("Catalogue messages")
struct CatalogueMessagesTests {

    @Test("A malformed feed never shows the parser reason")
    func malformedFeedHidesTheParserReason() {
        InterfaceLanguage.choose("en")
        defer { InterfaceLanguage.choose(nil) }
        let reason = "Expected BEGIN_OBJECT but was STRING at character 1"

        let sentence = CatalogueMessages.describe(.malformed(reason: reason))

        #expect(!sentence.contains(reason))
        #expect(sentence == "The catalogue could not be read.")
    }

    @Test("An unrecognised transport failure shows the fixed unreachable sentence")
    func unrecognisedTransportFailureShowsTheFixedSentence() {
        InterfaceLanguage.choose("en")
        defer { InterfaceLanguage.choose(nil) }
        struct SomeOtherError: Error, CustomStringConvertible {
            var description: String { "a raw description nobody should see" }
        }

        let sentence = CatalogueMessages.reachability(SomeOtherError())

        #expect(!sentence.contains("raw description"))
        #expect(sentence == "This server could not be reached.")
    }

    @Test("A refused status states the code, never a phrase in the device's language")
    func refusedStatusStatesTheCodeOnly() {
        InterfaceLanguage.choose("en")
        defer { InterfaceLanguage.choose(nil) }

        let sentence = CatalogueMessages.describe(.http(status: 404))

        #expect(sentence == "The server refused: 404.")
    }
}
