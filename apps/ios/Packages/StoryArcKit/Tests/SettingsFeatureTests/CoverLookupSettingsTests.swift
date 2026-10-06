import Foundation
import Testing

@testable import SettingsFeature
@testable import StoryArcCore

/// Task 3.1: the setting is off until a reader turns it on, and it names its providers.
struct CoverLookupSettingsTests {
    @Test("A reader who has never opened the setting has the lookup off")
    func isOffByDefault() {
        // `cover-art`: "a reader has never opened the cover-lookup setting ... no cover
        // request is made to any third party". The default is the requirement.
        #expect(!AppSettings.defaults.lookUpMissingCovers)
    }

    @Test("An older stored file reads as off rather than as consent")
    func anOlderFileReadsAsOff() throws {
        // A build that adds a setting must read what an earlier build wrote, and the field
        // is absent from every file written before this change. Absent must never mean yes.
        let older = #"{"appearance":"system","downloadOverWifiOnly":true}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(older.utf8))

        #expect(!settings.lookUpMissingCovers)
    }

    @Test("The row names every provider the lookup can reach")
    func namesEveryProvider() {
        // A fourth provider added without a word on this screen would be a request the
        // reader never agreed to, so the row is built from the enum rather than from a list
        // beside it.
        let shown = CoverLookupSettings.providerNames
        for provider in CoverLookupProvider.allCases {
            #expect(shown.contains(provider.displayName))
        }
    }

    @Test("The setting lives on the Privacy screen, because it decides what leaves")
    func livesUnderPrivacy() {
        #expect(SettingsAnchor.coverLookup.group == .privacy)
    }
}
