import Foundation
import StoryArcLicences

/// What the About tab can say about this build.
///
/// `settings-and-about`, *About*: the version and build, the byline as the one way to the
/// author, the repository, the licence, the support link stated once and never as a prompt,
/// every third-party library with its licence text, and a problem report pre-filled with
/// the version, the system and the device class and no personal data. The addresses are
/// the iOS `BuildInfo`'s, which is internal to `SettingsFeature`; the Mac does not link that
/// module, so they are copied here and `AboutTests` holds them.
enum MacAbout {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—" }
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—" }

    // Literal addresses, written once. A failed parse is a typo here, and the tests read them.
    static let author = URL(string: "https://github.com/me-cedric")
    static let repository = URL(string: "https://github.com/me-cedric/StoryArc")
    static let licence = URL(string: "https://github.com/me-cedric/StoryArc/blob/main/LICENSE")
    static let support = URL(string: "https://ko-fi.com/mecedric")

    /// The rows other than the byline, in the order they are drawn.
    static var links: [URL?] { [repository, licence, support] }

    /// The libraries someone else wrote that the Mac binary carries: libarchive through
    /// `Formats`, for RAR entries, and SMBClient through `LibraryFeature`'s `Smb`. Readium's
    /// web toolkit joins with the EPUB reader of wave 4. The fonts the iOS app bundles are not
    /// in the Mac build. `AboutTests` holds every name to an entry and a licence text in
    /// `packages/licences`, the inventory both phone apps read.
    static let linked = ["libarchive", "SMBClient"]

    /// The Mac's entries from the shared inventory.
    static func notices() throws -> [Notice] {
        try StoryArcLicences.forApple().filter { linked.contains($0.name) }
    }

    static func licenceText(for notice: Notice) -> String? {
        StoryArcLicences.text(for: notice)
    }

    /// The generated `THIRD_PARTY_NOTICES.md` the build copies into the app, or `nil` when it is
    /// missing or empty: a packaging bug the tab says rather than hides. Task 6.3.
    static func thirdPartyNotices(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }

    /// What a notices text lists: the name in the brackets of each table row the generator
    /// writes, `| [Name](address) | …`, as the Windows `Acknowledgements` reads it.
    static func components(of text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let row = line.drop { $0 == " " }
            guard row.hasPrefix("| ["), let end = row.firstIndex(of: "]") else { return nil }
            let name = row[row.index(row.startIndex, offsetBy: 3)..<end]
            return name.isEmpty ? nil : String(name)
        }
    }

    /// The tracker, pre-filled with three facts and nothing else.
    static func issue(
        version: String = version, build: String = build, system: String = systemName
    ) -> URL? {
        var components = URLComponents(string: "https://github.com/me-cedric/StoryArc/issues/new")
        let body = "StoryArc \(version) (\(build))\n\(system)\nMac\n\n"
        components?.queryItems = [URLQueryItem(name: "body", value: body)]
        return components?.url
    }

    /// "macOS 27.0.1": the system and its version, which is not personal.
    static var systemName: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
