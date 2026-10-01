import Foundation
import SwiftUI
import Testing

import StoryArcCore
@testable import LibraryFeature

/// Task 15.4: dates, relative times and joined lists on the catalogue screens followed the
/// process locale, not the reader's chosen one -- the same gap `ChosenLanguageFormattingTests`
/// already names for the settings screens.
///
/// `@MainActor` and run on the main actor's own serial queue for the reason that suite's own
/// note gives: `InterfaceLanguage.choose` is one value for the whole process, and `swift test`
/// runs every suite in parallel. A case here must not start inside the window another case
/// holds French open.
@MainActor
@Suite("Catalogue screens follow the chosen language", .serialized)
struct ChosenLanguageCatalogueTests {

    /// Every verbatim `String` reachable from a value -- the walk
    /// `SourceDetailSizeTests.rendered` and `ShelfCoverChoiceTests.strings` both use for a
    /// `Text` built from a `LocalizedStringKey` interpolation.
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

    private static let moment = Date(timeIntervalSince1970: 1_757_000_000)

    @Test("A cached notice's relative time follows the chosen language")
    func cachedNoticeFollowsFrench() {
        InterfaceLanguage.choose("fr")
        defer { InterfaceLanguage.choose(nil) }

        let french = Self.moment.formatted(.relative(presentation: .named).locale(.storyArc))
        let english = Self.moment.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US")))
        let shown = Self.strings(in: CachedNotice(refreshedAt: Self.moment).body)

        #expect(shown.contains(french), "the cached notice did not read \"\(french)\": \(shown.sorted())")
        #expect(!shown.contains(english), "the cached notice read the English relative time too")
    }

    @Test("A checked notice's relative time follows the chosen language")
    func checkedNoticeFollowsFrench() {
        InterfaceLanguage.choose("fr")
        defer { InterfaceLanguage.choose(nil) }

        let french = Self.moment.formatted(.relative(presentation: .named).locale(.storyArc))
        let shown = Self.strings(in: CheckedNotice(checkedAt: Self.moment).body)

        #expect(shown.contains(french), "the checked notice did not read \"\(french)\": \(shown.sorted())")
    }

    @Test("A joined list follows the chosen language's conjunction")
    func joinFollowsFrench() {
        InterfaceLanguage.choose("fr")
        defer { InterfaceLanguage.choose(nil) }

        #expect(localizedJoin(["Alice", "Bea"]) == "Alice et Bea")
    }

    @Test("The shared abbreviated date style follows the chosen language")
    func abbreviatedDateFollowsFrench() {
        InterfaceLanguage.choose("fr")
        defer { InterfaceLanguage.choose(nil) }

        let style = Date.FormatStyle(date: .abbreviated, time: .omitted)
        let french = Self.moment.formatted(style.locale(Locale(identifier: "fr_FR")))
        #expect(Self.moment.formatted(abbreviatedDateStyle) == french)
    }
}
