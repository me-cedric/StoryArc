import Foundation
import Testing

@testable import Persistence
@testable import SettingsFeature
import StoryArcCore

/// `library-portability` tasks 2.3, 3.3 and 6.8: each line the preview can draw, and the words it
/// draws it in. Android's `ImportPreviewLineRowsTest` asserts the same rows.
@MainActor
@Suite("Each line of the import preview is drawn, in four languages")
struct ImportPreviewLineViewTests {

    private let pin = CertificatePinNotice(host: "nas.local", sourceName: "Comics NAS")
    private let strangerPin = CertificatePinNotice(host: "evil.example", sourceName: nil)
    private let shelf = ImportedShelf(name: "Image Comics", membersAdded: 3)

    private var everyLine: [ImportPreviewLine] {
        [
            .certificatePins([pin, strangerPin]),
            .sourcesToAdd(["Comics NAS"]),
            .sourcesNeedingSignIn(["Comics NAS"]),
            .shelvesToAdd(["Crossover"]),
            .shelvesMerged([shelf]),
            .progress(add: 2, merge: 1),
            .themes(2),
            .covers(1),
            .settingsChange,
            .nothingNew,
        ]
    }

    private func keys(_ line: ImportPreviewLine) -> Set<String> {
        lookups(in: ImportPreviewLineView(line: line))
    }

    // MARK: Which key each line looks up

    @Test("The pin line is flagged as a change to what the app trusts, and says why")
    func thePinLine() {
        let keys = keys(.certificatePins([pin]))

        #expect(keys.contains("transfer.line.pins"))
        #expect(keys.contains("transfer.line.pins.note"))
    }

    @Test("A pin row names the host and the source it arrived with, or says there is none")
    func aPinRow() {
        #expect(lookups(in: PinRow(pin: pin)) == ["transfer.line.pin %@ %@"])
        #expect(lookups(in: PinRow(pin: strangerPin)) == ["transfer.line.pin.alone %@"])
    }

    @Test("The merge line counts the shelves, and each row says how many members it gains")
    func theMergeLine() {
        #expect(keys(.shelvesMerged([shelf])).contains("transfer.line.merged %lld"))
        #expect(lookups(in: MergedShelfRow(shelf: shelf)) == ["transfer.line.merged.added %lld"])
        #expect(arguments(of: "transfer.line.merged.added %lld", in: MergedShelfRow(shelf: shelf)) == [3])
    }

    @Test("Every other line looks up its own sentence")
    func theOtherLines() {
        #expect(keys(.sourcesToAdd(["a"])) == ["transfer.line.sources %lld"])
        #expect(keys(.sourcesNeedingSignIn(["a"])) == ["transfer.line.signIn %lld"])
        #expect(keys(.shelvesToAdd(["a"])) == ["transfer.line.shelves %lld"])
        #expect(keys(.themes(2)) == ["transfer.line.themes %lld"])
        #expect(keys(.covers(1)) == ["transfer.line.covers %lld"])
        #expect(keys(.settingsChange) == ["transfer.line.settings"])
        #expect(keys(.nothingNew) == ["transfer.line.nothing"])
    }

    @Test("Progress says what is added and what is merged, and leaves out a count of zero")
    func theProgressLine() {
        #expect(keys(.progress(add: 2, merge: 1))
            == ["transfer.line.progress.add %lld", "transfer.line.progress.merge %lld"])
        #expect(keys(.progress(add: 0, merge: 1)) == ["transfer.line.progress.merge %lld"])
    }

    // MARK: Four languages

    private struct Catalogue {
        let strings: [String: Any]

        init() {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appending(path: "Sources/SettingsFeature/Resources/Localizable.xcstrings")
            guard
                let data = try? Data(contentsOf: url),
                let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let strings = parsed["strings"] as? [String: Any]
            else { fatalError("the settings string catalogue is not readable at \(url.path)") }
            self.strings = strings
        }

        /// The text a language has for a key, whether a plain value or a plural's two forms.
        func texts(of key: String, in language: String) -> [String] {
            let localization = ((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?[language]
                as? [String: Any]
            if let value = (localization?["stringUnit"] as? [String: Any])?["value"] as? String {
                return [value]
            }
            let plural = (localization?["variations"] as? [String: Any])?["plural"] as? [String: Any] ?? [:]
            return plural.values.compactMap { form in
                ((form as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            }
        }
    }

    @Test("Every key a preview line looks up is written in English, French, German and Spanish")
    func everyLineKeyHasFourLanguages() {
        let catalogue = Catalogue()
        let looked = everyLine.reduce(into: Set<String>()) { $0.formUnion(keys($1)) }
            .union(lookups(in: PinRow(pin: pin)))
            .union(lookups(in: PinRow(pin: strangerPin)))
            .union(lookups(in: MergedShelfRow(shelf: shelf)))

        #expect(looked.count >= 14)
        for key in looked.sorted() {
            for language in ["en", "fr", "de", "es"] {
                let texts = catalogue.texts(of: key, in: language)
                #expect(!texts.isEmpty && texts.allSatisfy { !$0.isEmpty }, "\"\(key)\" has no \(language) text")
            }
        }
    }

    @Test("Every transfer string is written in all four languages, and a plural has both forms")
    func everyTransferKeyHasFourLanguages() {
        let catalogue = Catalogue()
        let keys = catalogue.strings.keys.filter { $0.hasPrefix("transfer.") }

        #expect(keys.count > 40)
        for key in keys.sorted() {
            for language in ["en", "fr", "de", "es"] {
                let texts = catalogue.texts(of: key, in: language)
                let expected = key.contains("%lld") && !key.contains("%@") && !key.contains("%lld %lld") ? 2 : 1
                #expect(texts.count >= 1 && texts.allSatisfy { !$0.isEmpty }, "\"\(key)\" has no \(language) text")
                if expected == 2 {
                    #expect(texts.count == 2, "\"\(key)\" is a plural and \(language) lacks a form")
                }
            }
        }
    }

    @Test("A plural's French, German and Spanish forms keep the count")
    func pluralsKeepTheCount() {
        let catalogue = Catalogue()
        for key in ["transfer.line.sources %lld", "transfer.line.merged.added %lld", "transfer.done.signIn %lld"] {
            for language in ["en", "fr", "de", "es"] {
                #expect(
                    catalogue.texts(of: key, in: language).allSatisfy { $0.contains("%lld") },
                    "\"\(key)\" in \(language) drops the count"
                )
            }
        }
    }
}
