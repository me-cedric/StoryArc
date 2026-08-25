public import Foundation

/// One thing StoryArc ships that someone else wrote.
///
/// Decoded from `notices.json`, which is the same file Android stages into its assets. A
/// list typed into Swift would drift from the audit, and the audit is the thing with a
/// legal consequence.
///
/// - Note: `why` is not decoration. `settings-and-about` asks for every library to be
///   listed; a dependency whose reason nobody can state is a dependency to remove, and
///   the About screen is where that becomes visible.
public struct Notice: Sendable, Equatable, Codable, Identifiable {
    public let name: String
    public let version: String?
    public let licence: String
    public let url: String
    public let platforms: [String]
    public let why: String

    public var id: String { "\(name)-\(licence)" }
}

/// Where the licence inventory is.
///
/// A resource-only target still needs one Swift file for `Bundle.module` to exist. This is
/// it, and it earns its place by being the only thing that knows the layout.
public enum StoryArcLicences {
    /// The bundle the inventory and the licence texts live in.
    ///
    /// Exposed for the same reason `StoryArcFonts.bundle` is: it justifies the public
    /// import, and a caller that needs a text this type does not name can still find it.
    public static var bundle: Bundle { .module }

    private struct File: Decodable {
        let notices: [Notice]
    }

    /// Everything to acknowledge on this platform.
    ///
    /// Filtered, because half the inventory is the other app's: telling an iOS reader that
    /// the app depends on the Readium *Kotlin* toolkit would be worse than telling them
    /// nothing.
    public static func forApple() -> [Notice] {
        guard let url = bundle.url(forResource: "notices", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return [] }
        return file.notices.filter { $0.platforms.isEmpty || $0.platforms.contains("ios") }
    }

    /// The licence text for an identifier, or `nil` if the file is missing.
    public static func text(for licence: String) -> String? {
        guard let url = bundle.url(
            forResource: licence, withExtension: "txt", subdirectory: "texts"
        ) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
