import Foundation
import Testing

@testable import SettingsFeature
import StoryArcCore

/// Task 15.7: whether a source's title count groups by locale.
///
/// **It already did.** The audit's evidence read `sources.detail %lld` and assumed a bare
/// `%lld` interpolation never groups -- true of `String(format:)`, which this app does not
/// use here. `Text("sources.detail \(count)", bundle: .module)` resolves through the modern
/// String Catalog, and that path formats an `Int` argument with its own locale-aware,
/// grouped `IntegerFormatStyle` by default. Measured directly: an explicit `format:
/// .number.locale(.storyArc)` interpolation changes the catalog key Swift generates --
/// `String(localized: "sources.detail \(5_000, format: .number)", bundle: .module)` resolves
/// to nothing and falls back to the literal key text, because the key no longer matches
/// `sources.detail %lld` -- while the bare `\(5_000)` this file already used resolves and
/// groups correctly against `en_US` and `de_DE` alike. So the fix for task 15.7 on iOS is
/// this test, not a code change: it is what proves the behaviour and would catch a rewrite
/// that moved this site onto `String(format:)` or dropped the String Catalog.
@Suite("Source detail counts already group by locale")
struct SourceDetailCountGroupingTests {

    @Test("A count of 5,000 groups with the English comma")
    func fiveThousandGroupsInEnglish() {
        let sentence = String(
            localized: "sources.detail \(5_000)",
            bundle: .module,
            locale: Locale(identifier: "en_US")
        )

        #expect(sentence == "5,000 titles", "read: \(sentence)")
    }

    @Test("The same count groups with the German period")
    func fiveThousandGroupsInGerman() {
        let sentence = String(
            localized: "sources.detail \(5_000)",
            bundle: .module,
            locale: Locale(identifier: "de_DE")
        )

        // The grouping separator follows `locale:` -- `IntegerFormatStyle` reads it
        // directly. Which translated table answers at all is a *different* negotiation
        // (the host's own preferred languages), unrelated to this test and unchanged by
        // it: on a host with only English installed, as this one is, the words stay
        // English while the digits still group the German way.
        #expect(sentence.hasSuffix("5.000 titles"), "read: \(sentence)")
    }

    @Test("A progress sentence groups both numbers")
    func progressGroupsBothNumbers() {
        let sentence = String(
            localized: "sources.detail.progress \(1_200) \(5_000)",
            bundle: .module,
            locale: Locale(identifier: "en_US")
        )

        #expect(sentence == "1,200 of 5,000 titles", "read: \(sentence)")
    }
}
