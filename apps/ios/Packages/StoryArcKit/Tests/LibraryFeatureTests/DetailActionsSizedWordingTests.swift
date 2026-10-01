import Foundation
import Testing

/// That the publication page's download offer states the size, the same as the share
/// browser's.
///
/// `publication-formats` asks a download offer to state the size the source stated, "rather
/// than as a zero" where none was stated. `DetailActions`'s `unavailableText` is a computed
/// property on a SwiftUI view with no host outside a simulator, so this reads its source text
/// and the catalogue it draws from — the same technique `RefusedFileWordingTests` uses for a
/// view with no test target at all, applied here to a property a test cannot otherwise drive.
/// Android's `DetailActionsTest.explanationResource` tests the same decision directly, because
/// that half of the logic was pulled out of its `@Composable`.
@Suite("The download offer states its size")
struct DetailActionsSizedWordingTests {
    private static let sourcePath: String = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/Tests/LibraryFeatureTests/this file → StoryArcKit
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        return directory
            .appending(path: "Sources/LibraryFeature/DetailActions.swift")
            .path
    }()

    private static let catalogPath: String = {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        return directory
            .appending(path: "Sources/LibraryFeature/Resources/Localizable.xcstrings")
            .path
    }()

    private func source() throws -> String {
        try #require(
            try? String(contentsOfFile: Self.sourcePath, encoding: .utf8),
            "\(Self.sourcePath) could not be read — has DetailActions.swift moved?"
        )
    }

    private func catalogue() throws -> [String: Any] {
        let data = try #require(
            try? Data(contentsOf: URL(fileURLWithPath: Self.catalogPath)),
            "\(Self.catalogPath) could not be read — has the LibraryFeature catalogue moved?"
        )
        let root = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(root["strings"] as? [String: Any])
    }

    @Test("The sentence checks fileSize before choosing which key to draw")
    func checksFileSize() throws {
        #expect(
            try source().contains("publication.fileSize"),
            """
            DetailActions no longer reads publication.fileSize when deciding the \
            download-unavailable sentence — the offer would go back to stating no size.
            """
        )
    }

    @Test("Both the sized and the sizeless key resolve in four languages", arguments: [
        "detail.unavailable", "detail.unavailable.sized %@",
    ])
    func keysResolve(key: String) throws {
        let strings = try catalogue()
        let entry = try #require(strings[key] as? [String: Any], "\(key) is not in the catalogue.")
        let localizations = try #require(entry["localizations"] as? [String: Any])
        for language in ["en", "fr", "de", "es"] {
            let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
            #expect(
                unit?["state"] as? String == "translated" && (unit?["value"] as? String)?.isEmpty == false,
                "\(key) has no translated \(language) value."
            )
        }
    }
}
