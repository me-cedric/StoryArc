import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature

import StoryArcCore

/// The five ways to add a source, under Settings' own button (task 17.9).
///
/// Moved from the library toolbar per task 1.2's own direction for where it belongs. The
/// library's own menu is walked the same way — `SourceKindsAreNamedTests` — for the reason
/// given there: `Text` keeps the `LocalizedStringKey` it was given, nothing public exposes
/// it, and `Mirror` is the only way in without a simulator.
@MainActor
@Suite("Settings' add-a-source button names the four kinds, the import and itself")
struct AddSourceButtonTests {
    private static func lookups() -> Set<String> {
        let button = AddSourceButton(
            onAddFolder: {},
            onImport: {},
            onAddCatalogue: {},
            onAddKavita: {},
            onAddShare: {}
        )

        var found: Set<String> = []
        var seen: Set<ObjectIdentifier> = []

        func walk(_ value: Any, depth: Int) {
            guard depth < 40 else { return }
            if type(of: value) == LocalizedStringKey.self {
                for child in Mirror(reflecting: value).children where child.label == "key" {
                    if let key = child.value as? String { found.insert(key) }
                }
                return
            }
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .class,
               !seen.insert(ObjectIdentifier(value as AnyObject)).inserted {
                return
            }
            for child in mirror.children { walk(child.value, depth: depth + 1) }
        }

        walk(button.body, depth: 0)
        return found
    }

    private static let kindKeys: Set<String> = [
        "sources.add.folder", "sources.add.catalogue", "sources.add.kavita", "sources.add.share",
    ]

    @Test("Each of the four kinds is named on the button")
    func eachKindIsNamed() {
        let drawn = Self.lookups()
        for key in Self.kindKeys {
            #expect(drawn.contains(key), "the button drew \(drawn.sorted())")
        }
    }

    @Test("The import row and the button's own label keep their own words")
    func importAndButtonAreNamed() {
        let drawn = Self.lookups()
        #expect(drawn.contains("sources.add.import"), "the button drew \(drawn.sorted())")
        #expect(drawn.contains("sources.add"), "the button drew \(drawn.sorted())")
    }

    @Test("Nothing else is dressed as a fifth kind")
    func onlyTheFourAreNamedAsKinds() {
        let drawn = Self.lookups()
        let claimed = drawn.filter { $0.hasPrefix("sources.add.") && $0 != "sources.add.import" }
        #expect(claimed == Self.kindKeys, "the button drew \(claimed.sorted())")
    }

    private static func localizations(of key: String) -> [String: Any]? {
        let catalogue = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/SettingsFeature/Resources/Localizable.xcstrings")
        guard
            let data = try? Data(contentsOf: catalogue),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let strings = parsed["strings"] as? [String: Any]
        else {
            fatalError("the settings string catalogue is not readable at \(catalogue.path)")
        }
        guard let record = strings[key] as? [String: Any] else { return nil }
        return record["localizations"] as? [String: Any] ?? [:]
    }

    @Test(
        "Every one of the six keys is written in all four languages",
        arguments: ["en", "fr", "de", "es"]
    )
    func everyLanguageCarriesAllSix(_ language: String) throws {
        for key in Self.kindKeys.union(["sources.add.import", "sources.add"]) {
            let localizations = try #require(
                Self.localizations(of: key),
                "the catalogue defines no \(key)"
            )
            let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
            let value = try #require(unit?["value"] as? String, "\(key) is empty in \(language)")
            #expect(!value.isEmpty)
        }
    }
}
