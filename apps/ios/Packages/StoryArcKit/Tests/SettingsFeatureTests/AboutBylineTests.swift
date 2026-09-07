import Foundation
import Testing

/// The byline names the handle, and it is the one control that opens the profile.
///
/// `settings-and-about` used to ask for the author's name and, separately, for a link to the
/// profile. The screen drew both, so two rows carried one fact and the row a reader looks at
/// first did nothing. The requirement now asks for one byline that is itself the control.
///
/// **This reads source text and a string catalogue, and that is a second choice.** The app
/// target has no test target, and `swift test` runs on the host with no simulator, so this
/// suite cannot compose `AboutSettings` and read what it drew. `WhatsNewWiringTests` records
/// the same constraint at length. Android composes its own `AboutGroup` in `AboutBylineTest`
/// and answers these claims by walking the tree.
///
/// It is a tripwire, not a proof. It asserts a `Link` is declared around the byline and that
/// one destination is named once; it never asserts a row was tappable on a screen.
@Suite("About byline")
struct AboutBylineTests {

    /// `apps/ios`, found from this file rather than from the working directory.
    ///
    /// `#filePath` and not a walk up from the process's directory, for the reason
    /// `WhatsNewWiringTests` records: this repository nests agent worktrees at
    /// `.claude/worktrees/<name>/`, and a walk that climbs looking for `apps/ios` climbs out
    /// of the checkout under test and validates the parent repository's copy.
    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/SettingsFeatureTests/this file → apps/ios
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory
    }()

    private static let stringsPath =
        "Packages/StoryArcKit/Sources/SettingsFeature/Resources/Localizable.xcstrings"
    private static let viewPath = "Packages/StoryArcKit/Sources/SettingsFeature/AboutSettings.swift"

    /// One source's text. Missing is a failure rather than a skip, and it names the path it
    /// looked at: a guard that cannot find what it guards passes for ever after a rename.
    private func source(_ relativePath: String) throws -> String {
        let url = Self.appleRoot.appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    /// The four values of one key in the catalogue, keyed by language.
    private func localizations(of key: String) throws -> [String: String] {
        let text = try source(Self.stringsPath)
        let data = try #require(text.data(using: .utf8), "the catalogue is not UTF-8")
        let root = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "the catalogue is not a JSON object"
        )
        let strings = try #require(root["strings"] as? [String: Any], "the catalogue has no strings")
        guard let entry = strings[key] as? [String: Any] else { return [:] }
        guard let all = entry["localizations"] as? [String: Any] else { return [:] }
        return all.compactMapValues { value in
            (value as? [String: Any]).flatMap { $0["stringUnit"] as? [String: Any] }
                .flatMap { $0["value"] as? String }
        }
    }

    @Test("The byline names the handle in all four languages")
    func handleEverywhere() throws {
        let values = try localizations(of: "about.author")

        #expect(values.count == 4, "the byline must be translated into all four languages")
        for (language, value) in values {
            #expect(value.contains("@me-cedric"), "\(language) does not name the handle: \(value)")
        }
    }

    @Test("No language still names a person a reader cannot look up")
    func noLegalName() throws {
        let values = try localizations(of: "about.author")

        for (language, value) in values {
            #expect(!value.contains("Cédric Meyer"), "\(language) still names the legal name")
        }
    }

    @Test("The row that duplicated the byline is gone from the catalogue")
    func noSeparateKey() throws {
        let values = try localizations(of: "about.authorLink")

        #expect(values.isEmpty, "about.authorLink is still declared, so a translator still owns it")
    }

    @Test("The byline is a link, and the only one to that address")
    func bylineIsTheLink() throws {
        let view = try source(Self.viewPath)

        #expect(
            view.contains("Link(destination: BuildInfo.author) {\n                    Text(\"about.author\""),
            "the byline is not wrapped in a Link to BuildInfo.author"
        )
        let destinations = view.components(separatedBy: "BuildInfo.author").count - 1
        #expect(destinations == 1, "BuildInfo.author is named \(destinations) times, and one row may own it")
        #expect(!view.contains("about.authorLink"), "the separate author row is still drawn")
    }
}
