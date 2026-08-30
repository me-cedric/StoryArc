import Foundation
import Testing

import StoryArcCore
@testable import Persistence

/// `settings-and-about` requires appearance to persist, a reset to leave sources,
/// downloads and reading progress alone, and — the one worth a test rather than a
/// glance — the reading theme to survive a change of app appearance.
///
/// A private `UserDefaults` suite rather than a mock: what is being asserted is that
/// values round-trip through storage, and that two stores stay out of each other's way.
@Suite("Settings store")
struct SettingsStoreTests {
    /// A private defaults suite, and the means to throw it away afterwards.
    private struct Suite {
        let settings: SettingsStore
        let reader: ReaderPreferences
        let defaults: UserDefaults
        let name: String

        func discard() { defaults.removePersistentDomain(forName: name) }
    }

    private func fresh() throws -> Suite {
        let name = "test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        return Suite(
            settings: SettingsStore(defaults: defaults),
            reader: ReaderPreferences(defaults: defaults),
            defaults: defaults,
            name: name
        )
    }

    @Test("Every setting comes back on the next launch")
    func roundTrip() throws {
        let suite = try fresh()
        defer { suite.discard() }

        suite.settings.save(
            AppSettings(
                appearance: .oledDark,
                language: "fr",
                turnPagesWithVolumeButtons: true,
                linkReadingThemeToAppearance: true
            )
        )

        let restored = suite.settings.settings()
        #expect(restored.appearance == .oledDark)
        #expect(restored.language == "fr")
        #expect(restored.turnPagesWithVolumeButtons)
        #expect(restored.linkReadingThemeToAppearance)
    }

    @Test("An untouched store is the documented defaults, not an empty value")
    func defaultsAreTheDefaults() throws {
        let suite = try fresh()
        defer { suite.discard() }

        let settings = suite.settings.settings()
        #expect(settings.appearance == .system)
        // `nil` rather than the current system language: the difference between "has
        // not chosen" and "chose whatever the system happened to be set to".
        #expect(settings.language == nil)
        #expect(!settings.turnPagesWithVolumeButtons)
        // Off, because `settings-and-about` says the two are separate and this is the
        // opt-in it then allows.
        #expect(!settings.linkReadingThemeToAppearance)
    }

    @Test("Settings written before a field existed still read")
    func forwardCompatible() throws {
        let suite = try fresh()
        defer { suite.discard() }

        // Swift's synthesised decoder fails on a missing key even where the property
        // has a default, so a build that adds a setting could not read what an earlier
        // build wrote. Losing a reader's settings is a poor trade for a stricter
        // decoder.
        suite.defaults.set(Data(#"{"appearance":"dark"}"#.utf8), forKey: "app.storyarc.settings")

        let settings = suite.settings.settings()
        #expect(settings.appearance == .dark)
        #expect(!settings.turnPagesWithVolumeButtons)
    }

    @Test("Changing appearance leaves the reading theme alone")
    func appearanceDoesNotTouchTheReadingTheme() throws {
        let suite = try fresh()
        defer { suite.discard() }

        // `settings-and-about`: "the reading theme is not overridden, because a dark app
        // chrome with a paper-white page is a legitimate preference". The two live in
        // separate stores, which is exactly why this is a test — nothing about the code
        // stops a future hand writing one from the other.
        let paper = ShelfSettings(theme: ReadingTheme(preset: .paper))
        suite.reader.save(ShelfMemory().remembering(paper, for: .reflowable, shelf: "Bone"))

        suite.settings.save(AppSettings(appearance: .oledDark))

        let theme = suite.reader.themes().theme(for: .reflowable, shelf: "Bone")
        #expect(theme.theme.preset == .paper)
    }

    @Test("A reset returns the settings and nothing else")
    func resetIsNarrow() throws {
        let suite = try fresh()
        defer { suite.discard() }

        // The claim the reset dialogue has to make: sources, downloads and reading
        // progress are not affected. It is true because `AppSettings` holds none of
        // them, and this asserts the neighbouring store survives.
        let calm = ShelfSettings(theme: ReadingTheme(preset: .calm)).settingFit(.width)
        suite.reader.save(ShelfMemory().remembering(calm, for: .fixedLayout, shelf: "Bone"))
        suite.settings.save(AppSettings(appearance: .light, turnPagesWithVolumeButtons: true))

        suite.settings.reset()

        #expect(suite.settings.settings() == .defaults)
        let bone = suite.reader.themes().theme(for: .fixedLayout, shelf: "Bone")
        #expect(bone.theme.preset == .calm)
        // A fit chosen while reading is a decision, not a setting, so a reset leaves it.
        #expect(bone.fit == .width)
    }

    // MARK: - The fit that used to be global

    @Test("The one fit the library used to share becomes the fixed-layout default")
    func legacyFitBecomesTheDefault() throws {
        let suite = try fresh()
        defer { suite.discard() }

        // What a build before the fit was per series left behind.
        suite.defaults.set("width", forKey: "app.storyarc.pageFit")

        let memory = suite.reader.themes()
        // Every shelf that has not been told otherwise inherits it, which is what
        // "global" meant — rather than every comic in the library reverting to
        // fit-to-screen on the day the reader updates.
        #expect(memory.theme(for: .fixedLayout, shelf: "Bone").fit == .width)
        #expect(memory.default(for: .fixedLayout).fit == .width)
    }

    @Test("The old fit is folded in once, and a later choice is not overwritten by it")
    func legacyFitIsFoldedInOnce() throws {
        let suite = try fresh()
        defer { suite.discard() }

        suite.defaults.set("width", forKey: "app.storyarc.pageFit")
        _ = suite.reader.themes()
        #expect(suite.defaults.string(forKey: "app.storyarc.pageFit") == nil)

        // The reader then sets the default to something else. A migration that ran
        // again would put fit-to-width back over it on the next read.
        let chosen = suite.reader.themes().default(for: .fixedLayout).settingFit(.original)
        suite.reader.save(suite.reader.themes().settingDefault(chosen, for: .fixedLayout))
        #expect(suite.reader.themes().default(for: .fixedLayout).fit == .original)
    }

    @Test("A shelf that chose its own fit keeps it when the old global one is folded in")
    func legacyFitDoesNotSweepAShelf() throws {
        let suite = try fresh()
        defer { suite.discard() }

        let chosen = ShelfSettings().settingFit(.height)
        suite.reader.save(ShelfMemory().remembering(chosen, for: .fixedLayout, shelf: "Bone"))
        suite.defaults.set("width", forKey: "app.storyarc.pageFit")

        let memory = suite.reader.themes()
        #expect(memory.theme(for: .fixedLayout, shelf: "Bone").fit == .height)
        #expect(memory.theme(for: .fixedLayout, shelf: "Blame!").fit == .width)
    }

    @Test("A library with no stored fit is left at fit-to-screen")
    func noLegacyFit() throws {
        let suite = try fresh()
        defer { suite.discard() }

        #expect(suite.reader.themes().default(for: .fixedLayout).fit == .screen)
    }
}
