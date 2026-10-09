import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature

import Persistence
import StoryArcCore

/// `library-sync` tasks 2.1, 2.4 and 4.4: the Sync section of the Sources group. Android's
/// `SyncRowsTest` makes the same claims.
@MainActor
@Suite("The Sync section")
struct SyncSettingsSectionTests {

    /// The catalogue key a `LocalizedStringKey` looks up.
    private static func key(_ value: LocalizedStringKey?) -> String? {
        guard let value else { return nil }
        return Mirror(reflecting: value).children.first { $0.label == "key" }?.value as? String
    }

    private static func line(_ status: LibrarySyncRunner.Status) -> String? {
        key(SyncSettingsSection.statusLine(status, place: "Kitchen NAS"))
    }

    private static let catalogue: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/SettingsFeature/Resources/Localizable.xcstrings")
        guard let data = try? Data(contentsOf: url),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = parsed["strings"] as? [String: Any]
        else { fatalError("the settings string catalogue is not readable at \(url.path)") }
        return strings
    }()

    private static func value(of key: String, in language: String) -> String? {
        let record = catalogue[key] as? [String: Any]
        let localizations = record?["localizations"] as? [String: Any]
        let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String
    }

    @Test("An unreachable place is said in words that name it, and off says nothing")
    func unreachableIsWords() {
        #expect(Self.line(.unreachable) == "sync.status.unreachable %@")
        #expect(Self.line(.off) == nil)
        #expect(Self.line(.idle) == "sync.status.idle")
        #expect(Self.line(.synced(Date())) == "sync.status.synced.recent %@")
    }

    @Test("A document the app cannot read is named for why")
    func refusalIsNamed() {
        #expect(Self.line(.refused(.newerThanThisApp(found: 9, understood: 1))) == "sync.status.newer")
        #expect(Self.line(.refused(.notALibraryDocument)) == "sync.status.notLibrary")
    }

    @Test("A library folder is refused with Android's sentence, and any other failure with its own")
    func folderRefusalIsNamed() {
        #expect(Self.key(SyncSettingsSection.refusal(SyncFolderRefusal.isLibrary)) == "sync.folderIsLibrary")
        #expect(Self.key(SyncSettingsSection.refusal(CocoaError(.fileReadNoPermission))) == "sync.folderRefused")
        let english = "This folder is one of your libraries. Choose another folder for sync."
        #expect(Self.value(of: "sync.folderIsLibrary", in: "en") == english)
    }

    @Test("A chosen share is named by its source, and a folder by its own name")
    func placeIsNamed() {
        let share = Source(displayName: "Kitchen NAS", kind: .networkShare, state: .connected)
        #expect(SyncSettingsSection.placeName(of: .share(sourceID: share.id), in: [share]) == "Kitchen NAS")
        #expect(SyncSettingsSection.placeName(of: .folder(name: "StoryArc Sync"), in: []) == "StoryArc Sync")
    }

    @Test("Search finds the Sync section in the Sources group")
    func searchFindsSync() {
        let match = SettingsGroup.search("sync")
        #expect(match.map(\.anchor) == [.sync])
        #expect(match.first?.group == .sources)
    }

    @Test("Every sync string is written in English, French, German and Spanish")
    func everyLanguage() throws {
        let keys = Self.catalogue.keys.filter { $0.hasPrefix("sync.") }
        #expect(keys.count >= 16)
        for key in keys {
            let english = try #require(Self.value(of: key, in: "en"), "\(key) has no English")
            for language in ["fr", "de", "es"] {
                let translated = try #require(Self.value(of: key, in: language), "\(key) has no \(language)")
                #expect(!translated.isEmpty)
                #expect(translated != english, "\(key) in \(language) is the English text")
            }
        }
    }

    @Test("The setting states what iOS does: no interval is promised for the background")
    func iOSSentence() throws {
        for language in ["en", "fr", "de", "es"] {
            let sentence = try #require(Self.value(of: "sync.when", in: language))
            #expect(sentence.contains("iOS"))
            #expect(!sentence.contains("15"))
        }
    }
}
