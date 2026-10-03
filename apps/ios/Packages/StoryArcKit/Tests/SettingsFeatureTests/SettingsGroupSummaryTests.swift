import SwiftUI
import Testing

@testable import SettingsFeature

import StoryArcCore

/// Task 19.2: the Reading summary row "describes the group but does not state its values",
/// and About's summary was the same fixed sentence. Neither had a test on either platform —
/// `SettingsGroup.summaryKey(for:_:readingDefaults:)` changed under 19.1's own commit with
/// nothing here to catch a revert back to the two constants.
///
/// `LocalizedStringKey` hides the key it holds; the walk is `DownloadsHeldNoteTests`' own
/// reflection, read once here rather than copied a third time.
@Suite("Settings group summaries state their values")
struct SettingsGroupSummaryTests {

    @Test("About states the version, not a fixed sentence")
    func aboutStatesTheVersion() {
        let key = SettingsGroup.about.summaryKey(for: AppSettings())

        #expect(Self.formatKey(of: key) != "settings.about.summary")
        #expect(Self.formatKey(of: key) == "about.version %@ %@")
    }

    @Test("Reading states the stored defaults, not a fixed sentence")
    func readingStatesItsStoredDefaults() {
        let key = SettingsGroup.reading.summaryKey(for: AppSettings(), readingDefaults: ShelfMemory())

        #expect(Self.formatKey(of: key) != "settings.reading.summary")
        #expect(Self.formatKey(of: key) == "settings.reading.summary.values %@ %@")
    }

    @Test("A different stored book preset changes what Reading states")
    func aDifferentStoredPresetChangesTheSummary() {
        let defaultMemory = ShelfMemory()
        let boldMemory = ShelfMemory()
            .settingDefault(ShelfSettings(theme: ReadingTheme(preset: .bold)), for: .reflowable)

        let defaultSummary = String(describing: SettingsGroup.reading.summaryKey(
            for: AppSettings(), readingDefaults: defaultMemory
        ))
        let boldSummary = String(describing: SettingsGroup.reading.summaryKey(
            for: AppSettings(), readingDefaults: boldMemory
        ))

        #expect(
            defaultSummary != boldSummary,
            Comment(rawValue: "Reading's summary reads the same whichever preset is stored —" +
                " it is a fixed sentence again, which is the defect 19.2 fixed.")
        )
    }

    /// The raw format string behind a `LocalizedStringKey`, read by reflection — the child
    /// labelled `"key"` is the literal, with `%@` where each interpolated value goes.
    private static func formatKey(of key: LocalizedStringKey) -> String {
        for child in Mirror(reflecting: key).children where child.label == "key" {
            if let name = child.value as? String { return name }
        }
        return ""
    }
}
