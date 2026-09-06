import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature

import Persistence
import StoryArcCore

/// A reader who chooses a language gets that language's numbers, sizes and dates too.
///
/// `localization` asks for "numbers, dates and file sizes" to follow the reader's language,
/// and the override moved only the words. ``StoryArcCore/Locale/storyArc`` was read by every
/// `String(localized:)` call site and by the SwiftUI environment, and by no formatter: a
/// reader on French saw French sentences with English grouping and an English date, one
/// screen at a time. Android has no such split — its override goes through
/// `createConfigurationContext`, which moves the whole configuration at once.
///
/// **The choice is one value for the whole process, and `.serialized` does not fence it.**
/// `.serialized` orders cases *within* a suite and nothing between two suites, exactly as
/// `KavitaClientTests` records, and `swift test` runs all 266 suites in one process in
/// parallel. The window a case here holds French open is not one formatting call either: it
/// is a whole SwiftUI body render and a reflection walk.
///
/// **What fences it is the main actor.** Every case that moves the choice, and every case
/// that reads a formatter following it, is `@MainActor` and synchronous, so one runs to its
/// end before the next starts. Those suites are `PlayerLabelsTests`, `StorageUsageTests`,
/// `StorageSummaryTests`, `SourceDetailSizeTests` and this one. **A new case that reads a
/// size, a date, a percentage or a spoken duration belongs in a `@MainActor` suite**, or it
/// will read French on a host that is not French, one run in a hundred.
@MainActor
@Suite("Sizes and dates follow the chosen interface language", .serialized)
struct ChosenLanguageFormattingTests {

    /// A moment with a French rendering that differs from its English one in every part.
    private static let moment = Date(timeIntervalSince1970: 1_757_000_000)

    private static let bytes: Int64 = 1_500_000

    /// French *on this device*: the chosen language, over the region the device already had.
    private static let french = onThisDevice("fr")

    /// The same, in English, so the control below holds on a device set to any region.
    private static let english = onThisDevice("en")

    /// Composed the way ``StoryArcCore/Locale/storyArc`` composes it, and that is deliberate.
    /// These two cases assert that the *formatter* asks that locale at all. Whether the
    /// composition is itself right is [theRegionSurvivesTheChoice]'s question, and that case
    /// compares against the device instead of against a second copy of the rule.
    private static func onThisDevice(_ language: String) -> Locale {
        var components = Locale.Components(locale: .autoupdatingCurrent)
        components.languageComponents.languageCode = Locale.LanguageCode(language)
        components.languageComponents.script = nil
        return Locale(components: components)
    }

    @Test("A size chosen in French is grouped and spelled the French way")
    func aSizeFollowsTheChoice() {
        InterfaceLanguage.choose("fr")
        defer { InterfaceLanguage.choose(nil) }

        #expect(
            DownloadStore.formatted(Self.bytes) == Self.size(in: Self.french),
            "the download size ignored the chosen language: \(DownloadStore.formatted(Self.bytes))"
        )
        // The unit comes from the language rather than from the region, so this holds on
        // any device: "Mo" is French for "MB" wherever the reader is.
        #expect(
            DownloadStore.formatted(Self.bytes).contains("Mo"),
            "the download size was not spelled in French: \(DownloadStore.formatted(Self.bytes))"
        )
        #expect(
            formattedBytes(Self.bytes).contains(Self.french.decimalSeparator ?? ","),
            "the storage figure ignored the chosen language: \(formattedBytes(Self.bytes))"
        )
    }

    @Test("A date chosen in French is written in French")
    func aDateFollowsTheChoice() {
        InterfaceLanguage.choose("fr")
        defer { InterfaceLanguage.choose(nil) }

        let shown = Self.renderedSourceDetail()
        #expect(
            shown.contains(Self.timestamp(in: Self.french)),
            "the last sync was not written in French: \(shown.sorted())"
        )
        // The control. Without it this case would pass on a screen that had lost the row,
        // and on a host already running in French.
        #expect(
            !shown.contains(Self.timestamp(in: Self.english)),
            "the last sync was written in English as well as French"
        )
    }

    /// The choice moves the language, and it moves nothing else.
    ///
    /// `localization` gives a date "the device's locale, calendar and time-zone conventions"
    /// and a size "locale digit grouping and unit conventions". A bare language tag answers
    /// neither. A reader in the United Kingdom who picks English read `4 Sep 2025 at 17:33`
    /// before the choice and `Sep 4, 2025 at 5:33 PM` after it, because `Locale("en")` carries
    /// the United States' date order and its 12-hour clock. The region, the clock and the
    /// numbering system stay the device's; only the language changes.
    @Test("A chosen language keeps the device's region, clock and calendar")
    func theRegionSurvivesTheChoice() {
        InterfaceLanguage.choose("fr")
        defer { InterfaceLanguage.choose(nil) }
        let device = Locale.autoupdatingCurrent

        #expect(
            Locale.storyArc.language.languageCode?.identifier == "fr",
            "the choice did not reach the locale: \(Locale.storyArc.identifier)"
        )
        #expect(
            Locale.storyArc.region == device.region,
            "the choice discarded the device's region: \(Locale.storyArc.identifier)"
        )
        #expect(
            Locale.storyArc.hourCycle == device.hourCycle,
            "the choice discarded the device's clock: \(Locale.storyArc.identifier)"
        )
        #expect(
            Locale.storyArc.calendar.identifier == device.calendar.identifier,
            "the choice discarded the device's calendar: \(Locale.storyArc.identifier)"
        )
    }

    /// The guard against over-fixing: "system" still means the device's own locale.
    @Test("A reader on system keeps the device's numbers, sizes and dates")
    func systemKeepsTheProcessLocale() {
        InterfaceLanguage.choose(nil)
        let process = Locale.autoupdatingCurrent

        #expect(
            DownloadStore.formatted(Self.bytes) == Self.size(in: process),
            "the download size stopped following the device: \(DownloadStore.formatted(Self.bytes))"
        )
        #expect(
            formattedBytes(Self.bytes).contains(process.decimalSeparator ?? "."),
            "the storage figure stopped following the device: \(formattedBytes(Self.bytes))"
        )
        #expect(
            Self.renderedSourceDetail().contains(Self.timestamp(in: process)),
            "the last sync stopped following the device"
        )
    }

    private static func size(in locale: Locale) -> String {
        bytes.formatted(.byteCount(style: .file, spellsOutZero: false).locale(locale))
    }

    private static func timestamp(in locale: Locale) -> String {
        moment.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    }

    /// Every verbatim `String` in the source detail screen's value tree, as
    /// [SourceDetailSizeTests] collects them: a formatted date is not a key, so it arrives
    /// as `Text`'s own storage rather than as a lookup.
    private static func renderedSourceDetail() -> Set<String> {
        let view = SourceDetail(
            source: Source(displayName: "Fixture", kind: .networkShare, state: .connected),
            diagnosis: SourceDiagnosis(
                state: .connected,
                lastSuccessfulSync: moment,
                failure: nil,
                itemCount: 3,
                downloadCount: 1,
                downloadedBytes: bytes,
                actions: [.testConnection, .refresh]
            ),
            perform: { _ in }
        )
        return strings(in: view.body)
    }

    private static func strings(in root: Any) -> Set<String> {
        var found: Set<String> = []
        var seen: Set<ObjectIdentifier> = []

        func walk(_ value: Any, depth: Int) {
            guard depth < 40 else { return }
            if let text = value as? String {
                found.insert(text)
                return
            }
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .class,
               !seen.insert(ObjectIdentifier(value as AnyObject)).inserted {
                return
            }
            for child in mirror.children { walk(child.value, depth: depth + 1) }
        }

        walk(root, depth: 0)
        return found
    }
}
