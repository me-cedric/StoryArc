import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature

/// Task 27.8 of `close-the-audited-gaps`: the sync status says when the last sync ran in one
/// whole sentence, in the reader's language, region and hour cycle.
@MainActor
@Suite("The moment of the last sync")
struct SyncMomentTests {
    private static let moment = Date(timeIntervalSince1970: 1_767_272_400)  // 2026-01-01 13:00 UTC
    private static let utc = TimeZone(identifier: "UTC") ?? .gmt
    private static let english = Locale(identifier: "en_US")
    private static let french = Locale(identifier: "fr_FR")

    private static func moment(at offset: TimeInterval, _ locale: Locale) -> SyncMoment {
        SyncMoment.of(moment, now: moment.addingTimeInterval(offset), locale: locale, timeZone: utc)
    }

    @Test("A sync from the last day says how long ago, in the locale's own words")
    func recentIsRelative() {
        #expect(Self.moment(at: 2 * 3600, Self.english) == .recent("2 hours ago"))
        #expect(Self.moment(at: 2 * 3600, Self.french) == .recent("il y a 2 heures"))
    }

    @Test("An older sync says the date and the time with the locale's hour cycle")
    func olderIsDateAndTime() {
        let older = 3 * SyncMoment.recentWindow
        #expect(Self.moment(at: older, Self.english) == .older("Jan 1, 2026 at 1:00\u{202F}PM"))
        #expect(Self.moment(at: older, Self.french) == .older("1 janv. 2026 à 13:00"))
    }

    @Test("The status line picks the sentence for the case, and the sentence adds no second 'at'")
    func statusLineKeys() {
        func key(_ value: LocalizedStringKey?) -> String? {
            guard let value else { return nil }
            return Mirror(reflecting: value).children.first { $0.label == "key" }?.value as? String
        }
        let recent = SyncSettingsSection.statusLine(
            .synced(Self.moment), place: "NAS", now: Self.moment.addingTimeInterval(60)
        )
        let older = SyncSettingsSection.statusLine(
            .synced(Self.moment), place: "NAS", now: Self.moment.addingTimeInterval(3 * SyncMoment.recentWindow)
        )

        #expect(key(recent) == "sync.status.synced.recent %@")
        #expect(key(older) == "sync.status.synced.on %@")
    }
}
