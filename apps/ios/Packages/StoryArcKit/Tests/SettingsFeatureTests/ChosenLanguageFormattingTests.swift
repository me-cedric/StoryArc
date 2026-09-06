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
/// **This suite is the only place that moves the process-wide choice**, and it is
/// `.serialized` so its own cases cannot overlap. `.serialized` orders cases *within* a
/// suite and nothing between two suites, exactly as `KavitaClientTests` records. Three
/// sibling cases read a size through the same helpers and would misread one taken during
/// this suite's window — `SourceDetailSizeTests.zeroIsANumber`,
/// `SourceDetailSizeTests.aRealSizeIsTheAppsOwn` and `StorageSummaryTests`' comparisons. The
/// window is one formatting call wide and the choice is put back before the case returns,
/// so it is small rather than absent; a one-off failure in one of those three names this
/// suite as the first thing to look at.
@MainActor
@Suite("Sizes and dates follow the chosen interface language", .serialized)
struct ChosenLanguageFormattingTests {

    /// A moment with a French rendering that differs from its English one in every part.
    private static let moment = Date(timeIntervalSince1970: 1_757_000_000)

    private static let bytes: Int64 = 1_500_000

    @Test("A size chosen in French is grouped and spelled the French way")
    func aSizeFollowsTheChoice() {
        InterfaceLanguage.choose("fr")
        defer { InterfaceLanguage.choose(nil) }
        let french = Locale(identifier: "fr")

        #expect(
            DownloadStore.formatted(Self.bytes) == Self.size(in: french),
            "the download size ignored the chosen language: \(DownloadStore.formatted(Self.bytes))"
        )
        #expect(
            formattedBytes(Self.bytes).contains(french.decimalSeparator ?? ","),
            "the storage figure ignored the chosen language: \(formattedBytes(Self.bytes))"
        )
    }

    @Test("A date chosen in French is written in French")
    func aDateFollowsTheChoice() {
        InterfaceLanguage.choose("fr")
        defer { InterfaceLanguage.choose(nil) }

        let shown = Self.renderedSourceDetail()
        #expect(
            shown.contains(Self.timestamp(in: Locale(identifier: "fr"))),
            "the last sync was not written in French: \(shown.sorted())"
        )
        // The control. Without it this case would pass on a screen that had lost the row,
        // and on a host already running in French.
        #expect(
            !shown.contains(Self.timestamp(in: Locale(identifier: "en"))),
            "the last sync was written in English as well as French"
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
