import Foundation
import Testing

import StoryArcCore
@testable import EpubReaderFeature

/// What a colour pairing will be like to read, said in words before the number that measures it.
///
/// `reading-themes` / *Custom colour* requires a refused pairing to be stated "with the measured
/// ratio stated". It does not require the ratio to be the *only* thing stated, and a reader
/// choosing a background colour cannot act on "4.7 to 1" — a number nobody can interpret is
/// decoration that looks like information. So a band leads, in plain words, and the measured ratio
/// follows it as supporting detail. Nothing is removed: the refusal keeps its measurement, because
/// a reader who is refused deserves to know by how much and a developer reading a bug report needs
/// the number.
///
/// **The two boundaries are the domain's own.** ``ReadingContrast/aaa`` at 7, which a derived text
/// colour aims for and every built-in preset clears, and ``ReadingContrast/aa`` at 4.5, below which
/// the sheet refuses the pairing outright. A band drawn at any other number would let the words and
/// the refusal disagree about the same pairing: the sheet would call a pairing comfortable and then
/// refuse it, or refuse it while calling it fine.
///
/// **The catalogue is read as a file, not resolved at run time.** The same limit
/// `SkipReasonCatalogueTests` records: a build copies an `.xcstrings` without compiling it, so
/// `String(localized:)` can answer with the key itself. What is asserted is that the catalogue holds
/// a translated value for every band in every language, which is what a reader needs and what the
/// run-time lookup would go looking for.
///
/// **The band has to be drawn, and drawn first.** A suite over the pure function alone was
/// vacuous against the requirement it was written for: both draw calls could be deleted and every
/// case still passed. So the section is also read as text, which is the tripwire
/// `ThemeAxisResetTests` and `ThemeSheetTest` already use for a layout no JVM or host test can
/// measure. The announcement is read the same way, because it is the only line that reaches a
/// reader who cannot see the sheet.
///
/// Android mirrors this suite in `PageColourBandTest`.
@Suite("A colour pairing says how it will read")
struct PageColourBandTests {

    /// The four `localization` names. English is the one every other falls back to.
    private static let languages = ["en", "fr", "de", "es"]

    // MARK: - The boundaries

    @Test("Seven to one reads comfortably, and just below it does not")
    func theUpperBoundary() {
        #expect(ReadingComfort.band(for: 7.01) == .easy, "above 7 to 1 is the comfortable band")
        #expect(
            ReadingComfort.band(for: ReadingContrast.aaa) == .easy,
            "7 to 1 itself is the comfortable band"
        )
        #expect(ReadingComfort.band(for: 6.99) == .tiring, "just below 7 to 1 leaves the comfortable band")
    }

    @Test("Four point five to one is still readable, and just below it is refused")
    func theLowerBoundary() {
        #expect(ReadingComfort.band(for: 4.51) == .tiring, "above 4.5 to 1 is the readable band")
        #expect(
            ReadingComfort.band(for: ReadingContrast.aa) == .tiring,
            "4.5 to 1 itself is the readable band"
        )
        #expect(ReadingComfort.band(for: 4.49) == .faint, "just below 4.5 to 1 is the band the sheet refuses")
    }

    @Test("The extremes of the scale land in the outer bands")
    func theExtremes() {
        #expect(ReadingComfort.band(for: 1) == .faint, "the worst possible pairing is refused")
        #expect(ReadingComfort.band(for: 21) == .easy, "black on white is the comfortable band")
    }

    // MARK: - What a reader is told

    @Test("A pairing the sheet accepts is never described as too faint")
    func anAcceptedPairingIsNotCalledFaint() {
        for hex in ReaderPalette.suggestedBackgrounds {
            let palette = ReaderPalette.derived(name: "", background: hex)
            #expect(palette.isReadable, "a suggested background is offered, so it must be usable")
            #expect(ReadingComfort.band(for: palette.contrast) != .faint, "an offered pairing is readable")
        }
    }

    @Test("A refused pairing is the faint band, and its refusal still states the measured ratio")
    func aRefusalStatesItsMeasurement() throws {
        let refused = ReaderPalette(name: "", background: "#FFFFFF", foreground: "#EEEEEE")
        #expect(!refused.isReadable, "near-white on white is below the floor")
        #expect(ReadingComfort.band(for: refused.contrast) == .faint, "a refused pairing is the faint band")

        let localizations = try #require(
            EpubCatalogue.localizations(of: "theme.pageColour.refused %@ %@"),
            "the catalogue no longer answers the refusal"
        )
        for language in Self.languages {
            let value = EpubCatalogue.value(of: localizations, in: language) ?? ""
            #expect(value.contains("%1$@"), "the refusal dropped the ratio it measured")
            #expect(value.contains("%2$@"), "the refusal dropped the floor it refused against")
        }
    }

    // MARK: - What the sheet draws, and what it says aloud

    @Test("The band is drawn, and drawn above the ratio that measures it, in both places")
    func theBandLeadsTheRatio() throws {
        let source = try Self.source("PageColourSection.swift")

        let inUse = try #require(
            source.range(of: "band(for: palette.contrast)"),
            "the sheet draws no band for the pairing in force, so the ratio stands alone again"
        )
        let ratio = try #require(
            source.range(of: #""theme.pageColour.ratio \("#),
            "the sheet no longer states the measured ratio of the pairing in force"
        )
        #expect(
            inUse.lowerBound < ratio.lowerBound,
            """
            The measured ratio is drawn before the words that explain it. `reading-themes` / \
            *Custom colour*: the sheet "says in plain words … AND the measured contrast ratio is \
            stated after those words rather than instead of them".
            """
        )

        let onRefusal = try #require(
            source.range(of: "band(for: refused)"),
            "a refused pairing draws no band, so the refusal opens with arithmetic again"
        )
        let refusal = try #require(
            source.range(of: #""theme.pageColour.refused \("#),
            "the refusal no longer states the ratio it measured"
        )
        #expect(
            onRefusal.lowerBound < refusal.lowerBound,
            """
            A refused pairing states its arithmetic before its plain words. The refusal is the \
            one moment a reader most needs the words first.
            """
        )
    }

    @Test("A refused pairing is announced in the order the sheet draws it")
    func theRefusalIsAnnouncedBandFirst() throws {
        let source = try Self.source("PageColourSection.swift")

        #expect(
            source.contains("ReadingComfort.band(for: candidate.contrast)"),
            """
            The refusal announcement carries no band. The tapped swatch does not move and the \
            reason renders at the foot of the section, so this announcement is the only thing a \
            VoiceOver reader hears — and without the band it is the arithmetic alone, which is \
            what `reading-themes` / *Custom colour* asks the sheet to lead away from.
            """
        )
        #expect(
            source.contains(#"AccessibilityNotification.Announcement("\(band) \(refusal)")"#),
            """
            The announcement does not speak the band before the refusal. What is heard and what \
            is drawn then describe one pairing in two different orders, and the reader who \
            cannot see the sheet gets the worse of the two.
            """
        )
    }

    // MARK: - Four languages

    @Test("Every band has a translated sentence in all four languages")
    func everyBandSpeaksFourLanguages() throws {
        for band in ReadingComfort.allCases {
            let localizations = try #require(
                EpubCatalogue.localizations(of: band.key),
                "the catalogue answers no sentence for one of the bands"
            )
            for language in Self.languages {
                let value = EpubCatalogue.value(of: localizations, in: language)
                #expect(value?.isEmpty == false, "a band is untranslated in one of the four languages")
            }
        }
    }

    @Test("The three bands say three different things in every language")
    func theBandsAreDistinct() {
        for language in Self.languages {
            let said = ReadingComfort.allCases.compactMap { band in
                EpubCatalogue.localizations(of: band.key)
                    .flatMap { EpubCatalogue.value(of: $0, in: language) }
            }
            #expect(Set(said).count == ReadingComfort.allCases.count, "two bands read the same in one language")
        }
    }

    @Test("The measured ratio is stated in all four languages, and keeps its number")
    func theRatioIsStatedFourLanguages() throws {
        let localizations = try #require(
            EpubCatalogue.localizations(of: "theme.pageColour.ratio %@"),
            "the catalogue no longer answers the measured ratio"
        )
        for language in Self.languages {
            let value = EpubCatalogue.value(of: localizations, in: language) ?? ""
            #expect(!value.isEmpty, "the ratio line is untranslated in one of the four languages")
            #expect(value.contains("%@"), "the ratio line no longer states the number it measured")
        }
    }

    /// One source file of the feature, read from disk.
    ///
    /// A tripwire rather than a proof, for the reason `ThemeAxisResetTests` gives: no host test
    /// can lay out a SwiftUI view, so the assertions over it say the band is written where the
    /// sheet draws it and never that a reader saw it. What a band *is* is proved above, over the
    /// pure function. The spellings asserted carry their argument lists, so no line of prose in
    /// the file can satisfy one by accident.
    private static func source(_ name: String) throws -> String {
        try String(
            contentsOf: EpubCatalogue.package.appending(path: "Sources/EpubReaderFeature/\(name)"),
            encoding: .utf8
        )
    }
}

/// The EPUB reader's own string catalogue, read from disk.
///
/// A local twin of `LibraryFeatureTests`' `LibraryFeatureSource`, kept small on purpose: this suite
/// needs one file and two lookups, and a shared helper across two packages would be a third place
/// for a path to point somewhere else.
private enum EpubCatalogue {

    /// The package root, reached from `#filePath` rather than found.
    ///
    /// So it is inside the checkout being compiled, by construction. Walking up looking for a marker
    /// leaves it: this repository nests agent worktrees at `.claude/worktrees/`.
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
