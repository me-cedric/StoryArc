import Foundation
import Testing

import Persistence
import StoryArcCore
@testable import EpubReaderFeature

/// That the reader's own named colour survives a preset tap and a whole-theme reset,
/// which drop only what is *in force*.
///
/// `reading-themes`, *Custom colour and the six presets*: "it is stored as a seventh,
/// user-named slot alongside the six presets rather than overwriting one". The slot lived
/// only inside `theme.custom`, which a preset tap drops on purpose — so the seventh card
/// vanished the moment the reader tapped any of the other six, and its own tap re-applied a
/// palette that was already gone. `EpubReaderModel.customPalette` is the slot now, kept
/// whether or not it is in force, and `theme.custom` is only what is on the page right now.
///
/// Android mirrors this suite in `CustomColourSlotTest`.
@MainActor
@Suite("The custom colour slot survives a preset tap and a reset")
struct CustomColourSlotTests {

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

    private func model(
        preferences: ReaderPreferences? = nil,
        series: String? = nil
    ) -> EpubReaderModel {
        let url = Self.corpus.appending(path: "ebooks/fixture.epub")
        return EpubReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: url.path),
                format: .epub,
                displayTitle: "fixture.epub",
                series: series,
                origin: .embedded
            ),
            url: url,
            preferences: preferences
        )
    }

    private let mine = ReaderPalette(name: "Mine", background: "#123456", foreground: "#FEDCBA")

    @Test("Tapping a preset drops what is in force, and keeps the slot")
    func aPresetTapKeepsTheSlot() {
        let reader = model()
        reader.adoptColours(mine)

        reader.adopt(.calm)

        #expect(
            reader.customPalette == mine,
            """
            The slot went with the preset. `reading-themes` keeps a custom colour "alongside \
            the six presets rather than overwriting one", and a preset that erases it is the \
            preset overwriting it.
            """
        )
        #expect(
            reader.theme.custom == nil,
            "Tapping one of the six presets left the reader's own colours on the page too."
        )
    }

    @Test("A whole-theme reset drops what is in force, and keeps the slot")
    func aResetKeepsTheSlot() {
        let reader = model()
        reader.adopt(.calm)
        reader.set(.lineSpacing, to: 2.4)
        reader.adoptColours(mine)

        reader.restoreTheme()

        #expect(reader.customPalette == mine, "The reset discarded the reader's own palette.")
        #expect(
            reader.theme.custom == nil,
            """
            The reset kept the reader's own colour in force, so the background did not \
            return to Calm's own value along with every other axis.
            """
        )
    }

    @Test("Tapping the seventh card puts the slot back in force")
    func theCardPutsItBackInForce() throws {
        let reader = model()
        reader.adoptColours(mine)
        reader.adopt(.calm)
        #expect(reader.theme.custom == nil, "setup: the preset tap should have dropped it")

        reader.adoptColours(try #require(reader.customPalette))

        #expect(
            reader.theme.custom == mine,
            "The card's own tap did not put the slot's palette back on the page."
        )
    }

    @Test("The slot is written to the shelf, and read back by the next reader on it")
    func theSlotPersists() throws {
        let suite = "CustomColourSlotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReaderPreferences(defaults: defaults)

        let first = model(preferences: preferences)
        first.adoptColours(mine)
        first.adopt(.calm)

        let second = model(preferences: preferences)

        #expect(
            second.customPalette == mine,
            """
            The slot did not reach the store, or did not come back. A reader who left the \
            book and opened it again lost their own named colour, with no way back to it.
            """
        )
    }

    @Test("Under Original the seventh card leaves for Paper and puts the slot in force")
    func theCardLeavesOriginal() throws {
        let reader = model()
        reader.adoptColours(mine)
        reader.adopt(.original)

        reader.adoptColours(try #require(reader.customPalette))

        #expect(
            reader.theme.custom == mine,
            """
            The seventh card drew under Original and its tap did nothing. Original takes no \
            colour, so the tap must leave it for Paper.
            """
        )
        #expect(reader.theme.preset == .paper)
    }

    @Test("The slot is there on a book of another series too")
    func theSlotIsNotPerSeries() throws {
        let suite = "CustomColourSlotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReaderPreferences(defaults: defaults)

        model(preferences: preferences, series: "First").adoptColours(mine)
        let other = model(preferences: preferences, series: "Second")

        #expect(
            other.customPalette == mine,
            """
            The slot stayed on the series it was made in. `reading-themes` stores it "alongside \
            the six presets", and the six presets are there on every shelf.
            """
        )
        #expect(other.theme.custom == nil, "The other series' own theme took the colour too.")
    }

    @Test("A palette in force from before the slot existed becomes the slot")
    func anOlderPaletteBecomesTheSlot() throws {
        let suite = "CustomColourSlotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReaderPreferences(defaults: defaults)
        model(preferences: preferences).adoptColours(mine)
        var older = preferences.themes()
        older.customPalette = nil
        preferences.save(older)

        let reader = model(preferences: preferences)

        #expect(
            reader.customPalette == mine,
            "A reader who made a colour before this update lost the seventh card for it."
        )
    }
}
