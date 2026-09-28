import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// A control carrying the current sort says that it is a sort, in every language this app
/// ships.
///
/// `library-browsing`, *An ordering says that it is an ordering*: the current sort "reads as an
/// ordering rather than as a value — a reader seeing the field name alone cannot tell a sort
/// from a filter", "and the same holds for grouping, which is neither".
///
/// **Nothing on this platform asserted it.** Android frames every ordering through
/// `ListOrder.chipLabel()` and pins it in four languages with `SortChipNamesAnOrderingTest`;
/// iOS frames it by a different route — the control's label names the *kind* of choice and the
/// field is its accessibility value — and `ListOrderTests` has twelve cases, none of them about
/// naming. A rewrite that put the field name in the label passed every test in this package,
/// which is why the 2026-09-12 recount scored the scenario `built, asserted by nothing`.
///
/// **What is asserted is a property, not a spelling.** A case comparing a label to `"Sort"`
/// would pin the copy in one language and pin nothing at all in the other three. So each
/// language is checked for the two things the requirement actually asks:
///
/// 1. the control's name is **not** any of the seven field names — that is the defect, stated
///    directly;
/// 2. the field name is **still** what the control is set to, because a control that said only
///    *Sort* would satisfy rule 1 by telling the reader less than before.
///
/// Both are needed. Rule 1 alone passes for a name of pure decoration; rule 2 alone passes for
/// the bare field name this guards against.
///
/// **The translations are read off the catalogue on disk**, for the reason
/// `SourceKindsAreNamedTests` records: `swift build` copies an `.xcstrings` without compiling
/// it, so `String(localized:)` answers with the key on the host.
@Suite("An ordering control says that it is an ordering")
struct OrderingNamesAnOrderingTests {

    private static let languages = ["de", "en", "es", "fr"]

    /// One key's value in every language the app ships.
    private static func strings(_ key: String) throws -> [String: String] {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = package.appending(path: "Sources/LibraryFeature/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: file)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let all = try #require(root["strings"] as? [String: Any])
        let entry = try #require(all[key] as? [String: Any], "\(key) is in no catalogue")
        let localizations = try #require(entry["localizations"] as? [String: Any])
        let values = localizations.compactMapValues { value in
            ((value as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
        }
        #expect(Set(values.keys) == Set(Self.languages), "\(key) is written in \(values.keys.sorted())")
        return values
    }

    /// Every field name, per language.
    private static func fieldNames() throws -> [String: Set<String>] {
        var byLanguage: [String: Set<String>] = [:]
        for sort in LibrarySort.allCases {
            for (language, word) in try strings(sort.titleKeyName) {
                byLanguage[language, default: []].insert(word)
            }
        }
        return byLanguage
    }

    @Test("No ordering is named by the field it is set to, in any language")
    func theNameIsNeverTheField() throws {
        let fields = try Self.fieldNames()
        let control = try Self.strings(OrderingNaming.orderingControl)

        for language in Self.languages {
            let name = try #require(control[language])
            let names = try #require(fields[language])
            #expect(
                !names.contains(name),
                "in \(language) an ordering control is called \(name), which is a field name"
            )
        }
    }

    @Test("Every ordering is still set to the field it orders by")
    func theFieldIsStillSaid() throws {
        // Rule 2. Without it a control named *Sort* and set to nothing would pass rule 1 by
        // telling the reader less than the bare field name did.
        for sort in LibrarySort.allCases {
            let naming = ListOrder(sort: sort).naming
            #expect(naming.value == sort.titleKeyName)
            #expect(naming.name != naming.value)
        }
    }

    @Test("All seven fields, not only the default a screenshot catches")
    func everyFieldIsFramed() {
        // A frame applied only to *Title* vanishes the moment a reader changes the sort —
        // which is exactly when they most need to be told what the control is.
        let named = LibrarySort.allCases.map { ListOrder(sort: $0).naming.name }

        #expect(named.count == 7)
        #expect(Set(named) == [OrderingNaming.orderingControl])
    }

    @Test("The curated order is not dressed as a sort")
    func theCuratedOrderNamesItself() throws {
        // `collections-and-reading-lists` makes the list's order the list's meaning, so *The
        // list's order* is already named as an ordering. Android's `ListOrder.chipLabel` keeps
        // the same asymmetry and says why.
        #expect(ListOrder.curated.naming.value == "shelves.list.order")

        let fields = try Self.fieldNames()
        let curated = try Self.strings("shelves.list.order")
        for language in Self.languages {
            let word = try #require(curated[language])
            #expect(!(try #require(fields[language])).contains(word))
        }
    }

    @Test("Grouping is neither a sort nor a filter, and is not called one")
    func groupingIsItsOwnWord() throws {
        // The scenario's last clause. One shared word for two controls that answer different
        // questions is the same defect wearing a second hat.
        let sorting = try Self.strings(OrderingNaming.orderingControl)
        let grouping = try Self.strings("library.grouping")

        for language in Self.languages {
            #expect(try #require(grouping[language]) != (try #require(sorting[language])))
        }
    }

    /// **Weaker than the cases above, and named as such**: that the two controls spend
    /// ``OrderingNaming`` rather than writing a key of their own is read from the source, for
    /// `SkippedNoticeAnnouncementTests`' reason — composing a `Menu` needs a window and
    /// `swift test` runs on the host. It is what stops a rewrite putting the field in the
    /// label while the rule above stays green beside it.
    @Test("Both ordering controls take their name from the one value")
    func bothControlsSpendTheNaming() {
        for file in ["ListOrder.swift", "LibraryBrowsingControls.swift"] {
            let package = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let path = package.appending(path: "Sources/LibraryFeature/\(file)")
            let text = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
            let code = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    guard let comment = line.range(of: "//") else { return String(line) }
                    return String(line[line.startIndex..<comment.lowerBound])
                }
                .joined(separator: "\n")

            #expect(
                !code.contains("Text(\"library.sort\""),
                "\(file) writes the ordering control's name itself instead of asking OrderingNaming"
            )
        }
    }
}
