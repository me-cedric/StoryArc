import Foundation
import Testing

import StoryArcCore
@testable import EpubReaderFeature

/// A background is shown before it is applied, not after.
///
/// `reading-themes` / *Choosing a background* asks for the background and the derived text
/// colour to be "shown in the preview before being applied". The section did the opposite:
/// the swatch called `onAdopt`, which reached the rendered page, and the sample under it then
/// drew the pairing already in force. That is a preview of the past — a reader could not see
/// what a colour would do to their book until it had already done it.
///
/// So a tap now sets a **pending** pairing, the sample, the band and the ratio describe that,
/// and one confirmation applies it. Nothing else about the section moves: a pairing below
/// 4.5 to 1 is still refused on that confirmation, with the band first and the measured ratio
/// after it, which `PageColourBandTests` owns.
///
/// **What each half of this suite proves.** ``PageColourSection/previewed(pending:inForce:)``
/// is a pure rule and is driven directly. What a tap *does* cannot be: no host test can lay
/// out a SwiftUI view, so the call sites are read as text, which is the tripwire
/// `PageColourBandTests` and `ThemeAxisResetTests` already use for this sheet. The spellings
/// asserted carry their argument lists, so no line of prose can satisfy one by accident.
///
/// Android mirrors this suite in `PageColourPreviewTest`.
@MainActor
@Suite("A background is previewed before it is applied")
struct PageColourPreviewTests {

    /// The four `localization` names. English is the one every other falls back to.
    private static let languages = ["en", "fr", "de", "es"]

    private let inForce = ReaderPalette.derived(name: "In force", background: "#FFFFFF")
    private let pending = ReaderPalette.derived(name: "Pending", background: "#101010")

    // MARK: - What the preview describes

    @Test("With nothing pending, the preview describes the pairing in force")
    func nothingPendingShowsThePairingInForce() {
        #expect(
            PageColourSection.previewed(pending: nil, inForce: inForce) == inForce,
            "the section stopped describing the reader's own colours once nothing was pending"
        )
    }

    @Test("A pending pairing is what the preview describes, and the page keeps the old one")
    func aPendingPairingIsWhatIsPreviewed() {
        #expect(
            PageColourSection.previewed(pending: pending, inForce: inForce) == pending,
            """
            The preview describes the pairing in force rather than the one the reader just \
            chose. `reading-themes`: the background and the derived text colour are "shown in \
            the preview before being applied".
            """
        )
    }

    @Test("A pending pairing is describable before any pairing has ever been applied")
    func aPendingPairingNeedsNoPairingInForce() {
        #expect(
            PageColourSection.previewed(pending: pending, inForce: nil) == pending,
            "the first colour a reader ever picks cannot be previewed, which is the one that most needs it"
        )
    }

    @Test("The specimen above the controls is drawn with the pairing being previewed")
    func theSpecimenDrawsThePendingPairing() {
        let inUse = ReadingTheme(preset: .paper, custom: inForce)

        #expect(
            ThemeAxesSheet.previewed(inUse, pending: pending).custom == pending,
            """
            The sheet's own specimen still draws the pairing in force while the three-line \
            sample under it draws the pending one, so one screen shows two answers for one \
            pairing and the larger one is stale. `ebook-reader` asks the specimen to update \
            "as an axis changes", and `reading-themes` asks a background to be "shown in the \
            preview before being applied".
            """
        )
        #expect(
            ThemeAxesSheet.previewed(inUse, pending: nil).custom == inForce,
            "the specimen stopped drawing the reader's own colours once nothing was pending"
        )
    }

    // MARK: - What a tap does, and what it does not do

    @Test("A swatch previews the pairing and does not put it on the page")
    func aSwatchPreviews() throws {
        let source = try Self.source("PageColourSection.swift")

        #expect(
            source.contains("preview(ReaderPalette.derived(name: chosenName, background: hex))"),
            """
            The background swatch no longer previews the pairing it makes. `reading-themes` \
            asks for the pairing to be shown before it is applied, and a swatch that applies \
            it leaves the sample below describing what already happened.
            """
        )
        #expect(
            !source.contains("adopt(ReaderPalette.derived(name: chosenName, background: hex))"),
            """
            The background swatch still applies the pairing straight to the page. The preview \
            under it then draws the palette already in force, which is the defect this suite \
            exists for.
            """
        )
    }

    @Test("Both ways into a background preview it — the swatches and the picker")
    func bothWaysIntoABackgroundPreviewIt() throws {
        let source = try Self.source("PageColourSection.swift")
        let previews = source.components(
            separatedBy: "preview(ReaderPalette.derived(name: chosenName, background: hex))"
        )

        #expect(
            previews.count == 3,
            """
            One of the two ways into a background stopped previewing it. There are two — the \
            suggested swatches and the colour picker — and a reader who reaches the page \
            through the one that still applies is shown a preview of what already happened.
            """
        )
    }

    @Test("The derived text colour is previewed as well as the background")
    func theDerivedTextColourIsPreviewedToo() throws {
        let source = try Self.source("PageColourSection.swift")

        #expect(
            source.contains("preview(palette.overriding(foreground: hex))"),
            """
            Overriding the derived text colour still applies straight to the page. \
            `reading-themes` names both halves of the pairing: the background "and the \
            derived text colour" are shown in the preview before being applied.
            """
        )
    }

    @Test("One confirmation is what applies the pairing")
    func oneConfirmationApplies() throws {
        let source = try Self.source("PageColourSection.swift")

        #expect(
            source.contains(#"Text("theme.pageColour.apply", bundle: .module)"#),
            """
            The section draws no way to apply what it is previewing, so a reader can choose a \
            colour and never reach it.
            """
        )
        #expect(
            source.contains("adopt(pending)"),
            "the confirmation applies something other than the pairing the reader was shown"
        )
    }

    // MARK: - Four languages

    @Test("The confirmation is named in all four languages")
    func theConfirmationSpeaksFourLanguages() throws {
        let localizations = try #require(
            PageColourCatalogue.localizations(of: "theme.pageColour.apply"),
            "the catalogue answers no name for the action that applies a previewed pairing"
        )
        for language in Self.languages {
            let value = PageColourCatalogue.value(of: localizations, in: language)
            #expect(value?.isEmpty == false, "the confirmation is untranslated in one of the four languages")
        }
    }

    /// One source file of the feature, read from disk. See `PageColourBandTests`.
    private static func source(_ name: String) throws -> String {
        try String(
            contentsOf: PageColourCatalogue.package.appending(path: "Sources/EpubReaderFeature/\(name)"),
            encoding: .utf8
        )
    }
}

/// The EPUB reader's own string catalogue, read from disk.
///
/// A second local twin of the one in `PageColourBandTests`, which is `private` to that file.
/// Kept rather than shared for the reason that one gives: two lookups do not earn a helper
/// package, and a shared one would be a third place for a path to point somewhere else.
private enum PageColourCatalogue {

    /// The package root, reached from `#filePath` rather than found.
    static var package: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func localizations(of key: String) -> [String: Any]? {
        let catalogue = package.appending(
            path: "Sources/EpubReaderFeature/Resources/Localizable.xcstrings"
        )
        guard
            let data = try? Data(contentsOf: catalogue),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let strings = parsed["strings"] as? [String: Any]
        else {
            fatalError("the EPUB reader's string catalogue is not readable at \(catalogue.path)")
        }
        guard let record = strings[key] as? [String: Any] else { return nil }
        return record["localizations"] as? [String: Any] ?? [:]
    }

    /// The translated value for one language, or nil where the language has none.
    static func value(of localizations: [String: Any], in language: String) -> String? {
        let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        guard unit?["state"] as? String == "translated" else { return nil }
        return unit?["value"] as? String
    }
}
