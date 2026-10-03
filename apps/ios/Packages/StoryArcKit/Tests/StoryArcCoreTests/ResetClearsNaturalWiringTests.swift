import Foundation
import Testing

/// That resetting settings actually clears Natural, on the app actions that own the reset.
///
/// Task 19.1: reset cleared the settings store and left `NaturalTheme`'s own key untouched,
/// so Appearance did not "go back to how it started" after all. The fix landed in commit
/// `442c3da2` with no test on either platform. This reads the call site, in the manner of
/// `QuickActionWiringTests` one file away: `apps/ios/project.yml` declares no app unit-test
/// target, so nothing in this package can construct `StoryArcApp` and call `resetSettings()`
/// directly. A tripwire, not a proof: it asserts the removal is written, never that
/// Appearance redrew. Android asserts the same call site in `ResetClearsNaturalWiringTest`.
@Suite("Resetting settings clears Natural")
struct ResetClearsNaturalWiringTests {

    /// `apps/ios`, from this file rather than the working directory — see
    /// `QuickActionWiringTests` for why the walk starts here instead of climbing from `cwd`.
    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory
    }()

    private func source(_ relativePath: String) throws -> String {
        let url = Self.appleRoot.appending(path: relativePath)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    /// Just `resetSettings()`'s own body, brace-matched.
    private func resetSettingsBody(_ source: String) throws -> String {
        let signature = "func resetSettings() {"
        let open = try #require(
            source.range(of: signature)?.upperBound,
            "StoryArcAppActions.swift no longer declares func resetSettings() — has it moved?"
        )
        var depth = 1
        var index = open
        while depth > 0 {
            index = source.index(after: index)
            if source[index] == "{" { depth += 1 } else if source[index] == "}" { depth -= 1 }
        }
        return String(source[open...index])
    }

    @Test("resetSettings clears the settings store")
    func clearsTheSettingsStore() throws {
        let body = try resetSettingsBody(try source("App/StoryArcAppActions.swift"))

        #expect(
            body.contains("settingsStore.reset()"),
            Comment(rawValue: "resetSettings() no longer calls settingsStore.reset() — the" +
                " settings store itself would survive a reset.")
        )
    }

    @Test("resetSettings clears Natural too, not only the settings store")
    func clearsNaturalToo() throws {
        let body = try resetSettingsBody(try source("App/StoryArcAppActions.swift"))

        #expect(
            body.contains("UserDefaults.standard.removeObject(forKey: NaturalTheme.storageKey)"),
            Comment(rawValue: "resetSettings() no longer removes NaturalTheme's own key." +
                " Appearance would stop going \"back to how it started\" the moment a reader" +
                " turns Natural on.")
        )
    }
}
