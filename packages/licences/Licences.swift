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
    /// The component's own copyright line.
    ///
    /// Separate from the licence body because `texts/` holds the SPDX *template* for each
    /// licence, and a template says `Copyright (c) <year> <owner>`. Shipping that
    /// placeholder discharges nothing — BSD and Apache both require the real notice to
    /// travel with the binary.
    public let copyright: String?
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
    ///
    /// The SPDX template, unsubstituted. Prefer ``text(for:)-(Notice)`` — this overload
    /// exists for a caller that has an identifier and no notice.
    public static func text(for licence: String) -> String? {
        guard let url = bundle.url(
            forResource: licence, withExtension: "txt", subdirectory: "texts"
        ) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// One component's licence, with its own copyright line in place of the template's.
    ///
    /// Substituting rather than prepending, so the notice reads as the project's own
    /// licence rather than as a licence with a note stapled to it.
    public static func text(for notice: Notice) -> String? {
        text(for: notice.licence).map { withCopyright($0, notice.copyright) }
    }

    /// Replaces an SPDX placeholder copyright line, or leaves the body alone.
    static func withCopyright(_ body: String, _ copyright: String?) -> String {
        guard let copyright, !copyright.isEmpty else { return body }
        var lines = body.components(separatedBy: "\n")
        guard let at = lines.firstIndex(where: { line in
            placeholders.contains { line.localizedCaseInsensitiveContains($0) }
        }) else {
            // No placeholder means the text already names its holder. Prepending a second
            // copyright line to such a text would state two, and one would be wrong.
            return body
        }
        lines[at] = copyright
        return lines.joined(separator: "\n")
    }

    private static let placeholders = ["<year>", "<owner>", "[yyyy]", "[name of copyright owner]"]
}
