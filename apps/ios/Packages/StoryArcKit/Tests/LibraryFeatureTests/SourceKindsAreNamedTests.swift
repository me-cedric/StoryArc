import Foundation
import SwiftUI
import Testing

@testable import LibraryFeature

import StoryArcCore

/// The four kinds of place are named, with a line each saying what they are.
///
/// `sources`' *Adding the first source* asks for "an empty state naming the four source types
/// with a one-line explanation of each", and the live delta puts that naming one level down:
/// "the four source types are named only after that secondary action is taken, where choosing
/// between them is the question being asked". The secondary action is ``AddSourceMenu``.
///
/// **The eight strings existed, in four languages, and nothing drew them.**
/// `SourceKind.titleKey` and `SourceKind.explanationKey` had no caller anywhere in the app;
/// the menu labelled its rows with the four *sheets'* titles instead, and said nothing at all
/// about what any of them is. This was the tenth piece of dead code found in this area.
///
/// **The menu's own body is walked, not its source file**, for ``SmbSheetAdviceTests``'
/// reason: a guard a comment satisfies is not a guard. The four translations are read off the
/// catalogue on disk, because `swift build` copies an `.xcstrings` without compiling it and
/// `String(localized:)` answers with the key on the host.
@MainActor
@Suite("The add-source menu names the four kinds and explains each")
struct SourceKindsAreNamedTests {

    /// Every localization key the menu's body carries.
    ///
    /// The reflection walk ``SmbSheetAdviceTests`` documents: `Text` keeps the
    /// `LocalizedStringKey` it was given, nothing public exposes it, and `Mirror` is the only
    /// way in without a simulator.
    private static func lookups() -> Set<String> {
        let menu = AddSourceMenu(
            addFolder: {},
            importFile: {},
            addCatalogue: {},
            addKavita: {},
            addShare: {}
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

        walk(menu.body, depth: 0)
        return found
    }

    /// The library catalogue on disk, for one key.
    ///
    /// Reached from `#filePath` rather than found: this repository nests agent worktrees at
    /// `.claude/worktrees/`, and a walk that looks upwards for a marker climbs out of the one
    /// under test.
    private static func localizations(of key: String) -> [String: Any]? {
        let catalogue = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/LibraryFeature/Resources/Localizable.xcstrings")
        guard
            let data = try? Data(contentsOf: catalogue),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let strings = parsed["strings"] as? [String: Any]
        else {
            fatalError("the library string catalogue is not readable at \(catalogue.path)")
        }
        guard let record = strings[key] as? [String: Any] else { return nil }
        return record["localizations"] as? [String: Any] ?? [:]
    }

    private static func value(of key: String, in language: String) throws -> String {
        let localizations = try #require(
            Self.localizations(of: key),
            "the catalogue defines no such key"
        )
        let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        return try #require(unit?["value"] as? String, "the key is empty in this language")
    }

    @Test("Each of the four kinds is named on the menu", arguments: SourceKind.allCases)
    func eachKindIsNamed(_ kind: SourceKind) {
        let drawn = Self.lookups()
        #expect(drawn.contains(kind.titleKeyName), "the menu drew \(drawn.sorted())")
    }

    @Test("Each of the four carries its one-line explanation", arguments: SourceKind.allCases)
    func eachKindIsExplained(_ kind: SourceKind) {
        let drawn = Self.lookups()
        #expect(drawn.contains(kind.explanationKeyName), "the menu drew \(drawn.sorted())")
    }

    @Test("Nothing else on the menu is dressed as a fifth kind")
    func onlyTheFourAreNamedAsKinds() {
        // `local-library` gives an imported copy a requirement of its own, and "On this
        // device" is not a place a reader configures — so the import row keeps its own words
        // and takes no `source.kind` line. The button's own label is checked too, so a walk
        // that found nothing at all cannot pass this.
        let drawn = Self.lookups()
        let claimed = drawn.filter { $0.hasPrefix("source.kind.") }
        #expect(claimed.count == SourceKind.allCases.count * 2, "the menu drew \(claimed.sorted())")
        #expect(drawn.contains("library.addSource"), "the walk found nothing: \(drawn.sorted())")
    }

    @Test(
        "Every title and every explanation is written in all four languages",
        arguments: ["en", "fr", "de", "es"]
    )
    func everyLanguageCarriesAllEight(_ language: String) throws {
        for kind in SourceKind.allCases {
            let title = try Self.value(of: kind.titleKeyName, in: language)
            let explanation = try Self.value(of: kind.explanationKeyName, in: language)
            #expect(!title.isEmpty, "a title is blank in this language")
            #expect(!explanation.isEmpty, "an explanation is blank in this language")
            #expect(title != explanation, "a title and its explanation are the same line")
        }
    }
}

/// The two keys, spelled as strings so a test can compare them.
///
/// ``SourceKind/titleKey`` and ``SourceKind/explanationKey`` are `LocalizedStringKey`, which
/// carries its key privately. These build the same names from the case's own raw value, so a
/// kind added tomorrow reaches this suite rather than being silently skipped by it.
extension SourceKind {
    fileprivate var titleKeyName: String { "source.kind.\(rawValue).title" }
    fileprivate var explanationKeyName: String { "source.kind.\(rawValue).explanation" }
}
