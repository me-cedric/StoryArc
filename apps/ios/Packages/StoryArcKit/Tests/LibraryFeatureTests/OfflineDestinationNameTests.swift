import Foundation
import Testing

/// The place that holds what opens with no network has one name, and it is a place.
///
/// The owner's decision for `one-vocabulary-in-four-languages` task 4.3: the destination is
/// named by its **location** — *on this device* — and the **promise** — *can be read without
/// a connection* — moves to the empty state, which is the one surface with room to read it.
/// Before the decision iOS named a transfer (*Nothing downloaded*) where Android named a
/// place, and Android named a capability where iOS named a place. Either name alone is
/// defensible; two names for one place is the defect.
///
/// **These read the catalogues as files**, the trade `StatedAxisTests` makes and explains: the
/// words a screen is given are text, and text can be checked exactly. This suite reads
/// `SettingsFeature`'s catalogue as well as its own, because the count and the empty state are
/// one vocabulary drawn on two screens, and a guard that watched one of them would pass on the
/// day the other moved.
///
/// Android asserts the same two claims over `values*/strings.xml` in
/// `OfflineDestinationNameTest`.
@Suite("The offline destination has one name")
struct OfflineDestinationNameTests {

    /// How each language says the destination's location.
    private static let location = [
        "en": "on this device",
        "fr": "sur cet appareil",
        "de": "auf diesem gerät",
        "es": "en este dispositivo",
    ]

    /// How each language says the promise the empty state carries.
    private static let promise = [
        "en": "without a connection",
        "fr": "sans connexion",
        "de": "ohne Verbindung",
        "es": "sin conexión",
    ]

    private static func catalogue(_ relativePath: String) throws -> [String: Any] {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = package.appending(path: relativePath)
        let text = try String(contentsOf: file, encoding: .utf8)
        let data = try #require(text.data(using: .utf8))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(json?["strings"] as? [String: Any], "\(relativePath) holds no strings.")
    }

    /// One key's value in every language the app ships.
    private static func strings(_ key: String, in relativePath: String) throws -> [String: String] {
        let all = try catalogue(relativePath)
        let entry = try #require(all[key] as? [String: Any], "\(key) is not in the catalogue.")
        let localizations = try #require(entry["localizations"] as? [String: Any])
        return localizations.compactMapValues { value in
            let unit = (value as? [String: Any])?["stringUnit"] as? [String: Any]
            return unit?["value"] as? String
        }
    }

    /// The word each language uses for the act of fetching a file.
    private static let transfer = [
        "en": "download", "fr": "téléchargé", "de": "heruntergeladen", "es": "descarga",
    ]

    private static let settings = "Sources/SettingsFeature/Resources/Localizable.xcstrings"
    private static let library = "Sources/LibraryFeature/Resources/Localizable.xcstrings"

    // MARK: - The count names what it counts

    /// Settings' own row states a figure, and the figure is downloads.
    ///
    /// **This row deliberately does not name the device, and that is not an oversight.** The
    /// destination is named by its location; this figure is not the destination. It weighs
    /// `DownloadStore.bytesOnDisk()` — the app's own downloads and imports — and not a folder
    /// the reader added, which is readable offline and is counted nowhere here. A sweep on
    /// 2026-09-04 photographed "Nothing on this device" over a device holding nine
    /// publications and moved these two strings to name the transfer instead. Naming the
    /// place here would put that back.
    @Test("Both halves of the count name the transfer, in every language", arguments: [
        "settings.downloads.none",
        "settings.downloads.summary %@",
    ])
    func theCountNamesTheTransfer(key: String) throws {
        let values = try Self.strings(key, in: Self.settings)
        #expect(values.count == 4, "Every language the app ships has to answer this.")
        for (language, sentence) in values {
            let wanted = try #require(Self.transfer[language], "\(language) is not a shipped language.")
            #expect(
                sentence.lowercased().contains(wanted),
                "\(language) states \(key) as “\(sentence)”, which does not name the transfer."
            )
        }
        for (language, sentence) in values {
            let place = try #require(Self.location[language], "\(language) is not a shipped language.")
            #expect(
                !sentence.lowercased().contains(place),
                "\(language) states \(key) as “\(sentence)”, which names a place the figure does not count."
            )
        }
    }

    /// The count keeps exactly one argument, and it is the figure.
    @Test("The count carries one placeholder in every language")
    func theCountKeepsItsPlaceholder() throws {
        let values = try Self.strings("settings.downloads.summary %@", in: Self.settings)
        for (language, sentence) in values {
            #expect(
                sentence.components(separatedBy: "%@").count == 2,
                "\(language) states the count as “\(sentence)”, which is not one figure."
            )
        }
    }

    // MARK: - The empty state carries the promise

    /// The location alone does not say what the place is for, and the empty state has the room.
    @Test("The empty state names the location and promises reading with no connection")
    func theEmptyStateCarriesThePromise() throws {
        let values = try Self.strings("library.empty.onDevice", in: Self.library)
        #expect(values.count == 4, "Every language the app ships has to answer this.")
        for (language, sentence) in values {
            let place = try #require(Self.location[language], "\(language) is not a shipped language.")
            let offline = try #require(Self.promise[language], "\(language) is not a shipped language.")
            #expect(
                sentence.lowercased().contains(place),
                "\(language) states the empty shelf as “\(sentence)”, which does not name the location."
            )
            #expect(
                sentence.lowercased().contains(offline.lowercased()),
                "\(language) states the empty shelf as “\(sentence)”, which drops the promise."
            )
        }
    }
}
