import Foundation
import Testing

/// Five states the two apps used to word differently, now worded the same in four languages
/// (`one-vocabulary-in-four-languages` 4.2, `close-the-audited-gaps` 15.11, D31).
///
/// **Both catalogues are read as files.** A compose rule or a SwiftUI view holds one locale,
/// and `swift test` on this host resolves `String(localized:)` against the system language, so
/// a claim about four languages at once can only be read off the catalogue. Android's
/// `ReconciledWordingTest` asserts the same table over its own `strings.xml`: an edit to one
/// platform that the other does not follow fails one suite or the other.
///
/// A placeholder is written `{n}` for a count and `{s}` for a string, so iOS's `%lld`/`%@` and
/// Android's `%1$d`/`%1$s` compare as the one thing they are.
@Suite("The reconciled wording rows read the same on both platforms")
struct ReconciledWordingTests {

    struct Row: Sendable, CustomTestStringConvertible {
        let ios: String
        let catalogue: String
        let android: String
        let module: String
        let words: [String: String]

        var testDescription: String { ios }
    }

    static let rows: [Row] = [
        Row(
            ios: "library.cell.progress %lld", catalogue: "LibraryFeature",
            android: "library_cell_progress", module: "library",
            words: [
                "en": "{n}%% read", "fr": "{n}%% lu", "de": "{n}%% gelesen", "es": "{n}%% leído",
            ]
        ),
        Row(
            ios: "reader.cannotOpen", catalogue: "ReaderFeature",
            android: "reader_cannot_open", module: "reader",
            words: [
                "en": "This title could not be opened.",
                "fr": "Ce titre n’a pas pu être ouvert.",
                "de": "Dieser Titel lässt sich nicht öffnen.",
                "es": "No se pudo abrir este título.",
            ]
        ),
        Row(
            ios: "reader.matte", catalogue: "ReaderFeature",
            android: "reader_matte", module: "reader",
            words: [
                "en": "Colour behind a comic page",
                "fr": "Couleur derrière une page de BD",
                "de": "Farbe hinter einer Comicseite",
                "es": "Color detrás de una página de cómic",
            ]
        ),
        Row(
            ios: "sources.remove.title %@", catalogue: "SettingsFeature",
            android: "sources_remove_title", module: "settings",
            words: [
                "en": "Remove {s}?", "fr": "Retirer {s} ?", "de": "{s} entfernen?",
                "es": "¿Quitar {s}?",
            ]
        ),
        Row(
            ios: "sources.removeDownloads.title %@", catalogue: "SettingsFeature",
            android: "sources_remove_downloads_title", module: "settings",
            words: [
                "en": "Remove downloads from {s}?",
                "fr": "Supprimer les téléchargements de {s} ?",
                "de": "Downloads von {s} entfernen?",
                "es": "¿Quitar las descargas de {s}?",
            ]
        ),
    ]

    private static let apps = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private static func neutral(_ text: String) -> String {
        text.replacingOccurrences(of: "%lld", with: "{n}")
            .replacingOccurrences(of: "%1$d", with: "{n}")
            .replacingOccurrences(of: "%@", with: "{s}")
            .replacingOccurrences(of: "%1$s", with: "{s}")
            .replacingOccurrences(of: "\\'", with: "'")
    }

    private static func iosValue(_ row: Row, _ language: String) throws -> String {
        let url = apps.appending(
            path: "ios/Packages/StoryArcKit/Sources/\(row.catalogue)/Resources/Localizable.xcstrings"
        )
        let data = try Data(contentsOf: url)
        let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try #require(parsed["strings"] as? [String: Any])
        let record = try #require(strings[row.ios] as? [String: Any], "no \"\(row.ios)\" in \(row.catalogue)")
        let locales = try #require(record["localizations"] as? [String: Any])
        let unit = (locales[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        return neutral(try #require(unit?["value"] as? String, "\(row.ios) is empty in \(language)"))
    }

    private static func androidValue(_ row: Row, _ language: String) throws -> String {
        let folder = language == "en" ? "values" : "values-\(language)"
        let url = apps.appending(path: "android/feature/\(row.module)/src/main/res/\(folder)/strings.xml")
        let text = try String(contentsOf: url, encoding: .utf8)
        let pattern = try NSRegularExpression(
            pattern: "<string name=\"\(row.android)\"[^>]*>(.*?)</string>",
            options: [.dotMatchesLineSeparators]
        )
        let range = NSRange(text.startIndex..., in: text)
        let match = try #require(pattern.firstMatch(in: text, range: range), "\(row.android) is not in \(folder)")
        return neutral(String(text[try #require(Range(match.range(at: 1), in: text))]))
    }

    @Test("iOS words the row as agreed, in every language", arguments: rows)
    func iosHoldsTheAgreedWords(row: Row) throws {
        for (language, expected) in row.words {
            #expect(try Self.iosValue(row, language) == expected, "\(row.ios) in \(language)")
        }
    }

    @Test("Android words the row the same way iOS does", arguments: rows)
    func androidMatchesIos(row: Row) throws {
        for language in row.words.keys {
            #expect(
                try Self.androidValue(row, language) == Self.iosValue(row, language),
                "\(row.android) in \(language) differs from \(row.ios)"
            )
        }
    }
}
