import Foundation
import Testing

@testable import LibraryFeature

/// Every field a reader types a server address or a secret into says what it is.
///
/// **The defect, measured rather than supposed.** An XCUITest dump of the Kavita add-source
/// sheet on 2026-09-11 reported `textFields: [""]` and `secureTextFields: [""]`. Each field
/// draws its name as a separate headline above it and then hides the field's own label, so
/// VoiceOver announced "text field" and gave no hint of what to type — on the one form in the
/// app where a wrong character means a refused connection. `native-experience`'s *Screen
/// reader* scenario asks that "every control has a meaningful label".
///
/// **Read as source, like ``LibraryGroupingWiringTests``.** A composition reports what the
/// inputs it was given drew; what has to hold here is a *declaration* — that the modifier is
/// written, and written with the key the visible headline uses, so the spoken name and the
/// drawn name cannot drift. What VoiceOver actually says is not settled by any test in this
/// repository, and `reader-theming-and-page-transitions` task 7.6 is where that is tracked.
///
/// **Only text fields.** A segmented or inline `Picker` vends each segment as its own element,
/// so a label on the container may do nothing or may rename the segments, and which of the two
/// cannot be established without a screen reader. Those controls are deliberately untouched.
struct SpokenFieldLabelsTests {

    private var kavita: String { LibraryFeatureSource.code(of: "Sources/LibraryFeature/KavitaSheet.swift") }
    private var catalogue: String { LibraryFeatureSource.code(of: "Sources/LibraryFeature/CatalogueSheet.swift") }

    /// One sheet, and the keys it has to speak.
    private struct Sheet {
        let file: String
        let source: String
        let keys: [String]
    }

    private var spoken: [Sheet] {
        [
            Sheet(
                file: "KavitaSheet.swift",
                source: kavita,
                keys: ["kavita.address.label", "kavita.key.label"]
            ),
            Sheet(
                file: "CatalogueSheet.swift",
                source: catalogue,
                keys: [
                    "catalogue.address.label",
                    "catalogue.signIn.token",
                    "catalogue.signIn.user",
                    "catalogue.signIn.password",
                ]
            ),
        ]
    }

    /// The hints each sheet has to speak once, and hide the second copy of.
    private var hinted: [Sheet] {
        [
            Sheet(file: "KavitaSheet.swift", source: kavita, keys: ["kavita.address.hint", "kavita.key.hint"]),
            Sheet(file: "CatalogueSheet.swift", source: catalogue, keys: ["catalogue.address.hint"]),
        ]
    }

    @Test("Every address and secret field carries a spoken name")
    func everyFieldIsNamed() {
        for sheet in spoken {
            #expect(!sheet.keys.isEmpty, "\(sheet.file) names no key, so this test asserts nothing")
            for key in sheet.keys {
                #expect(
                    sheet.source.contains("accessibilityLabel(Text(\"\(key)\""),
                    "\(sheet.file) does not speak \(key)"
                )
            }
        }
    }

    /// The spoken name is the drawn name, so a rewording moves both at once.
    @Test("A field's spoken name is the key its own headline draws")
    func theSpokenNameIsTheDrawnName() {
        for sheet in spoken {
            for key in sheet.keys {
                let drawn = sheet.source.components(separatedBy: "Text(\"\(key)\"").count - 1
                let spokenOnce = sheet.source.contains("accessibilityLabel(Text(\"\(key)\"")
                #expect(drawn >= 2 && spokenOnce, "\(key) is not both drawn and spoken in \(sheet.file)")
            }
        }
    }

    /// A hint is spoken once. It is the field's hint, and the footnote that draws it is hidden.
    ///
    /// Both would otherwise be read, one after the other, and a reader would hear the same
    /// sentence twice on a form they are already struggling with.
    @Test("A hint drawn under a field is not also read as its own element")
    func aHintIsSpokenOnce() {
        for sheet in hinted {
            for hint in sheet.keys {
                #expect(
                    sheet.source.contains("accessibilityHint(Text(\"\(hint)\""),
                    "\(sheet.file) does not hint \(hint)"
                )
            }
            #expect(
                sheet.source.components(separatedBy: "accessibilityHidden(true)").count - 1 == sheet.keys.count,
                "\(sheet.file) hides a different number of footnotes than it has hints"
            )
        }
    }

    /// Nothing spoken is spoken in one language only.
    @Test("Every spoken name exists in all four languages")
    func everySpokenNameIsTranslated() throws {
        let catalogueFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/LibraryFeature/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogueFile)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(root["strings"] as? [String: Any])

        let keys = spoken.flatMap(\.keys) + hinted.flatMap(\.keys)
        #expect(keys.count == 9, "the key list moved; this count is what stops it emptying unnoticed")
        for key in keys {
            let entry = try #require(strings[key] as? [String: Any], "\(key) is in no catalogue")
            let localizations = try #require(entry["localizations"] as? [String: Any])
            #expect(
                Set(localizations.keys) == ["de", "en", "es", "fr"],
                "\(key) is spoken in \(localizations.keys.sorted())"
            )
        }
    }
}
