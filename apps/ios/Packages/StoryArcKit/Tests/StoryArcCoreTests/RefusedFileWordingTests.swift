import Foundation
import Testing

/// That the refused-file alert says its six sentences in the reader's own language.
///
/// `localization` requires every sentence a reader is shown to resolve through a catalogue in
/// all four supported languages. `RefusedFile.swift` drew six English literals instead: the
/// alert's title, its button, and the three message branches. Android's `RefusedFileDialog`
/// has drawn `R.string.open_in_*` since it was written, so iOS was the only side left.
///
/// **This reads the app's source text and the app's catalogue**, and that is a deliberate
/// second choice, for the reason ``ShellWiringTests`` sets out one file away: the app target
/// has no test target of its own, and `pnpm test:ios` runs `swift test` over this package
/// alone. `pnpm strings:ios` checks that a key the source asks for is answered in four
/// languages; nothing checked that these six sentences asked at all.
///
/// It is a tripwire, not a proof. It asserts that each branch draws a key and that the
/// catalogue answers it in four languages. It never asserts that a reader of French would
/// call the French sentence good.
@Suite("Refused file wording")
struct RefusedFileWordingTests {

    /// The app target's directory, found from this file rather than from the working directory.
    ///
    /// `#filePath` and not a walk up from the process's directory, for the reason
    /// ``ShellWiringTests`` records: this repository nests agent worktrees at
    /// `.claude/worktrees/<name>/`, and a walk that climbs looking for `apps/ios/App` climbs
    /// out of the checkout under test and validates the parent repository's copy.
    private static let appDirectory: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/StoryArcCoreTests/this file → apps/ios
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory.appendingPathComponent("App")
    }()

    /// The five keys the alert draws, written as the catalogue stores them.
    ///
    /// A `Text("key \(a)")` is stored under the key SwiftUI derives, which is the stem plus one
    /// `%@` per interpolation — the same normalisation `scripts/ios-strings.mjs` performs.
    /// Named to pair with Android's `open_in_*`, which is the same alert on the other platform.
    private static let keys = [
        "open.in.refused.title",
        "open.in.dismiss",
        "open.in.unsupported %@ %@ %@",
        "open.in.unreadable %@ %@",
        "open.in.protected %@",
    ]

    /// The four languages `localization` names. English is the one every other falls back to.
    private static let languages = ["en", "fr", "de", "es"]

    /// `RefusedFile.swift`'s text.
    ///
    /// Missing is a failure rather than a skip, and it names the path it looked at. A guard
    /// that cannot find what it guards passes for ever after a rename.
    private func source() throws -> String {
        let path = Self.appDirectory.appendingPathComponent("RefusedFile.swift").path
        return try #require(
            try? String(contentsOfFile: path, encoding: .utf8),
            "\(path) could not be read — has RefusedFile.swift moved?"
        )
    }

    /// The app catalogue's entries, by key.
    private func catalogue() throws -> [String: Any] {
        let path = Self.appDirectory
            .appendingPathComponent("Resources/Localizable.xcstrings").path
        let data = try #require(
            try? Data(contentsOf: URL(fileURLWithPath: path)),
            "\(path) could not be read — has the app catalogue moved?"
        )
        let root = try #require(
            try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            "\(path) is not a JSON object."
        )
        return try #require(root["strings"] as? [String: Any], "\(path) has no strings table.")
    }

    @Test("The alert draws no English literal")
    func noVerbatim() throws {
        let text = try source()
        #expect(
            !text.contains("Text(verbatim:"),
            """
            RefusedFile.swift still draws a verbatim string. A reader of French is shown \
            English there. The alert's title and its button are keys now — see \
            `open.in.refused.title` and `open.in.dismiss` in App/Resources/Localizable.xcstrings.
            """
        )
    }

    @Test("Every branch of the alert draws a key")
    func everyBranchDrawsAKey() throws {
        let text = try source()
        let missing = Self.keys.filter { !text.contains($0.components(separatedBy: " ")[0]) }
        #expect(
            missing.isEmpty,
            """
            RefusedFile.swift draws no key for \(missing). The title, the button and each of \
            the three message branches resolve through the catalogue, the way Android's \
            RefusedFileDialog resolves R.string.open_in_*.
            """
        )
    }

    @Test("The catalogue answers every key in four languages")
    func catalogueAnswersInFourLanguages() throws {
        let strings = try catalogue()
        // A guard over an empty table passes for ever. This is the assertion that fails if the
        // catalogue stops being read at all.
        #expect(strings.count > 20, "The app catalogue holds \(strings.count) keys, which is too few to be itself.")
        for key in Self.keys {
            let entry = try #require(
                strings[key] as? [String: Any],
                "The app catalogue does not define \(key)."
            )
            let localizations = try #require(
                entry["localizations"] as? [String: Any],
                "\(key) carries no localizations."
            )
            for language in Self.languages {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String
                #expect(
                    unit?["state"] as? String == "translated" && value?.isEmpty == false,
                    "\(key) has no translated \(language) value."
                )
            }
        }
    }

    @Test("The protected refusal forecloses the field it does not draw")
    func protectedForeclosesTheField() throws {
        let strings = try catalogue()
        let entry = strings["open.in.protected %@"] as? [String: Any]
        let localizations = entry?["localizations"] as? [String: Any]
        let unit = (localizations?["en"] as? [String: Any])?["stringUnit"] as? [String: Any]
        let value = try #require(
            unit?["value"] as? String,
            "open.in.protected %@ carries no English value."
        )
        #expect(
            value.contains("nothing to enter"),
            """
            The English `open.in.protected %@` states the protection and stops. Android says \
            one sentence more — `ProtectedAudiobookPromptsForNothingTest` asserts \
            "nothing to enter" — because it forecloses the expectation rather than leaving \
            the reader waiting for a field that is never coming.
            """
        )
    }
}
