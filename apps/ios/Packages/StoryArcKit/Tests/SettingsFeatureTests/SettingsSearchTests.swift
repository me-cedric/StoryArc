import Testing

@testable import SettingsFeature

/// The settings index, which is a hand-written list and therefore the kind of thing that
/// rots quietly.
///
/// Mirrored case for case by Android's `SettingsSearchTest`. The two indexes are the one
/// place a reader can tell the platforms apart without opening a screen, so they are
/// asserted against the same expectations rather than merely written to the same spec.
@Suite("Settings search")
struct SettingsSearchTests {
    @Test("An empty query lists every group and no single setting")
    func emptyQueryListsGroups() {
        let matches = SettingsGroup.search("")

        #expect(matches.map(\.group) == SettingsGroup.allCases)
        #expect(matches.allSatisfy { $0.anchor == nil })
    }

    @Test("Whitespace is not a query")
    func whitespaceIsEmpty() {
        #expect(SettingsGroup.search("   ").count == SettingsGroup.allCases.count)
    }

    @Test("A term that names a setting points at the setting, not at its group")
    func settingTermPointsAtTheSetting() {
        let matches = SettingsGroup.search("volume")

        #expect(matches.count == 1)
        #expect(matches.first?.anchor == .volumeButtons)
        // The group path, which is what makes the match actionable.
        #expect(matches.first?.group == .reading)
    }

    @Test("Case is not part of a query")
    func searchIgnoresCase() {
        #expect(SettingsGroup.search("VOLUME").first?.anchor == .volumeButtons)
    }

    @Test("A query nothing answers returns nothing")
    func unmatchedQueryReturnsNothing() {
        #expect(SettingsGroup.search("zzzz").isEmpty)
    }

    /// The test that keeps the index honest: an anchor no term reaches is a highlight
    /// nothing can ask for, and the screen would carry the tint code for a row search
    /// cannot send anyone to.
    @Test("Every setting the screens can highlight is reachable by search")
    func everyAnchorIsReachable() {
        let indexed = Set(SettingsGroup.searchable.compactMap(\.match.anchor))

        #expect(indexed == Set(SettingsAnchor.allCases))
    }

    @Test("Every group is reachable by search")
    func everyGroupIsReachable() {
        let indexed = Set(SettingsGroup.searchable.filter { $0.match.anchor == nil }.map(\.match.group))

        #expect(indexed == Set(SettingsGroup.allCases))
    }

    @Test("Every term finds the entry that claims it")
    func everyTermFindsItsEntry() {
        for entry in SettingsGroup.searchable {
            for term in entry.terms {
                let found = SettingsGroup.search(term).map(\.id)
                #expect(found.contains(entry.match.id), "\"\(term)\" does not find \(entry.match.id)")
            }
        }
    }

    /// An anchor carries its own group, so a match cannot claim a setting is on a screen
    /// that does not show it. Asserted rather than assumed, because the index writes the
    /// group by hand nowhere — and the day it does, this fails.
    @Test("A setting match agrees with its anchor about where the setting lives")
    func matchAgreesWithItsAnchor() {
        for anchor in SettingsAnchor.allCases {
            #expect(SettingMatch(anchor: anchor).group == anchor.group)
        }
    }

    @Test("A group match and a setting match are told apart by their identity")
    func identityDistinguishesGroupsFromSettings() {
        #expect(SettingMatch(group: .reading).id != SettingMatch(anchor: .volumeButtons).id)
    }
}
