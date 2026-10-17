import Formats
import Foundation
import Testing

@testable import StoryArc

/// Every menu title and every sentence the library shows when something goes wrong is in
/// the built app in the four languages `localization` names.
///
/// `SWIFT_EMIT_LOC_STRINGS` adds a key to the catalogue only when Xcode's editor builds,
/// never from `xcodebuild`, so a key used in code and absent from the catalogue renders as
/// its own name with no gate to say so. Wave 2 found 133 such keys. This reads each
/// language's compiled table from the app bundle and fails by key and language.
@Suite("Localization")
struct LocalizationTests {
    static let languages = ["en", "fr", "de", "es"]

    /// Keys the catalogue must hold, as the compiler writes them (`%@`, `%lld`).
    static let keys: [String] = CommandTable.all.map(\.titleKey) + SettingsIndex.entries.map(\.titleKey) + [
        "desktop.menu.go", "desktop.menu.reader",
        "desktop.refused.protected %@", "desktop.refused.passwordProtected %@",
        "desktop.refused.solidArchive %@", "desktop.refused.damaged %@",
        "desktop.refused.unsupported %@ %@ %@", "desktop.refused.unreadable %@ %@",
        "desktop.source.offline %@", "desktop.source.needsAccess %@", "desktop.source.chooseAgain",
        "desktop.restore.missing %@", "desktop.drop.listed %lld %@",
        "desktop.home.keepReading", "desktop.home.upNext",
        "desktop.reader.pageLabel %lld %lld", "desktop.detail.continue %lld %lld",
        "desktop.accent", "desktop.accent.brand", "desktop.accent.system",
        "desktop.reading.clickZones",
        "desktop.skipped %lld", "desktop.skipped.one %@", "desktop.skipped.show", "desktop.skipped.dismiss",
        "desktop.skipped.list", "desktop.skipped.done",
    ] + [
        SkipReason.unsupportedFormat("CB7"), .notThere, .formatNotRecognised, .archivePasswordProtected,
        .archiveUnreadable, .pdfUnopenable, .contentProtected, .unknown,
    ].map(SkippedWords.key(for:)) + [
    ]

    @Test("Each key is translated in each language", arguments: languages)
    func translated(language: String) throws {
        let path = try #require(
            Bundle.main.path(forResource: language, ofType: "lproj"), "no \(language).lproj in the app"
        )
        let bundle = try #require(Bundle(path: path))
        let missing = Self.keys.filter { key in
            bundle.localizedString(forKey: key, value: "\u{0}missing", table: nil) == "\u{0}missing"
        }
        #expect(missing.isEmpty, "\(language) lacks \(missing)")
    }
}
