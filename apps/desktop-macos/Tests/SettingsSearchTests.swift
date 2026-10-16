import Testing

@testable import StoryArc

/// The preferences search of task 2.21.
@Suite("Settings search")
struct SettingsSearchTests {
    @Test("A word shows only the settings that match, grouped under their tabs")
    func matchesAreGrouped() {
        let groups = SettingsIndex.grouped("accent")

        #expect(groups.map(\.tab) == [.appearance])
        #expect(groups.first?.entries.map(\.id) == ["accent"])
    }

    @Test("A synonym finds the setting, and the search is case-insensitive")
    func synonyms() {
        #expect(SettingsIndex.matches("Colour").map(\.id) == ["accent"])
        #expect(SettingsIndex.matches("WIFI").map(\.id) == ["metered"])
        #expect(SettingsIndex.matches("turn").map(\.id).contains("clickZones"))
    }

    @Test("An empty query lists everything in toolbar order; a word nothing matches lists nothing")
    func emptyAndNone() {
        #expect(SettingsIndex.grouped("").map(\.tab) == SettingsTab.allCases)
        #expect(SettingsIndex.grouped("   ").count == SettingsTab.allCases.count)
        #expect(SettingsIndex.matches("zebra").isEmpty)
        #expect(SettingsIndex.grouped("zebra").isEmpty)
    }

    @Test("Every entry's tab exists and ids are unique")
    func indexIsSound() {
        let ids = SettingsIndex.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
        for tab in SettingsTab.allCases {
            #expect(SettingsIndex.entries.contains { $0.tab == tab }, "\(tab) has no entry")
        }
    }
}
