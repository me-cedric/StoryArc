import Foundation
import Testing

/// That what changed is presented from the shell, and that About cannot record anything.
///
/// ``WhatsNewTests`` pins the *decision* — once per version, never on a first launch, always
/// recorded. It cannot pin either of the two claims below, and both are claims about wiring
/// rather than about a value:
///
/// - The sheet is presented **from `AppShell`**, on the launch after an update, at one large
///   detent. Delete the `.sheet` and every `swift test` suite, `swiftlint --strict` and
///   `xcodebuild build` stay green while the app never tells anybody anything again.
/// - Reaching it from About "does not change what the app considers seen". The way that is
///   held is that ``WhatsNewHistory`` has no store — but nothing stops a later edit from
///   handing it one, and the test that would then fail does not exist unless it is this one.
///
/// **So this reads source text, and that is a deliberate second choice**, for the reasons
/// `ShellWiringTests` sets out: the app target has no test target, `swift test` runs on the
/// host with no simulator so a `TabView` cannot be composed here, and the only thing that
/// renders the shell is a UI test on a booted simulator, which no gate runs.
///
/// It is a tripwire, not a proof. It asserts a presentation is declared and a store is
/// absent; it never asserts a sheet appeared. `ScreenshotTests.testCaptureWhatsNew` is what
/// photographs it on a device, and this file can be deleted the day that run is a gate.
@Suite("What's new wiring")
struct WhatsNewWiringTests {

    /// `apps/ios`, found from this file rather than from the working directory.
    ///
    /// `#filePath` and not a walk up from the process's directory, for the reason
    /// `ShellWiringTests` records: this repository nests agent worktrees at
    /// `.claude/worktrees/<name>/`, and a walk that climbs looking for `apps/ios` climbs out
    /// of the checkout under test and validates the parent repository's copy.
    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/SettingsFeatureTests/this file → apps/ios
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory
    }()

    /// One source's text. Missing is a failure rather than a skip, and it names the path it
    /// looked at: a guard that cannot find what it guards passes for ever after a rename.
    private func source(_ relativePath: String) throws -> String {
        let url = Self.appleRoot.appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    @Test("The shell presents what changed, at one large detent")
    func theShellPresentsIt() throws {
        let shell = try source("App/AppShell.swift")
        #expect(
            shell.contains(".sheet(item: $whatsNew)"),
            """
            AppShell no longer presents the what's-new sheet. A reader who updates learns
            nothing, and nothing else in this repository fails.
            """
        )
        #expect(
            shell.contains("WhatsNewSheet(release: release)"),
            "The what's-new sheet is presented with something other than WhatsNewSheet."
        )
        #expect(
            shell.contains(".presentationDetents([.large])"),
            """
            The sheet lost its single large detent. A medium detent shows two rows and a
            drag handle, which reads as a card to be opened rather than a thing being said.
            """
        )
    }

    @Test("The decision is taken once, in the shell, and nowhere else")
    func theDecisionIsTakenOnce() throws {
        let shell = try source("App/AppShell.swift")
        #expect(
            shell.contains("WhatsNew.onLaunch()"),
            "AppShell no longer asks whether this launch is the one that says what changed."
        )
        for file in try settingsFeatureSources() where file != "WhatsNew.swift" {
            let text = try source("Packages/StoryArcKit/Sources/SettingsFeature/\(file)")
            // `WhatsNew.onLaunch(` rather than `onLaunch`, and the precision is the point:
            // `WhatsNewSheet.swift`'s comment links ``WhatsNew/onLaunch(store:)`` — with a
            // slash — to explain why swiping the sheet away costs nothing, and a naive
            // search failed on the prose that documents the very rule it guards. The same
            // trap `ShellWiringTests` fell into with the role it removed.
            #expect(
                !text.contains("WhatsNew.onLaunch("),
                """
                \(file) calls WhatsNew.onLaunch. It records the version as seen, so a second
                caller inside Settings would mark a version seen because somebody opened About.
                """
            )
        }
    }

    @Test("No screen in Settings can record a version as seen")
    func aboutCannotRecord() throws {
        for file in try settingsFeatureSources() where file != "WhatsNew.swift" {
            let text = try source("Packages/StoryArcKit/Sources/SettingsFeature/\(file)")
            #expect(
                !text.contains("WhatsNewStore"),
                """
                \(file) reaches the what's-new store. `settings-and-about`: reaching the
                screen from About "does not change what the app considers seen", and the way
                that is held is that no screen here has a store to write to.
                """
            )
        }
    }

    /// Every Swift file in `SettingsFeature`, so a new screen is covered without being named.
    ///
    /// A hand-written list is a list that goes stale the first time somebody adds a file, and
    /// the file they add is exactly the one that would slip through.
    private func settingsFeatureSources() throws -> [String] {
        let directory = Self.appleRoot.appendingPathComponent("Packages/StoryArcKit/Sources/SettingsFeature")
        let names = try #require(
            try? FileManager.default.contentsOfDirectory(atPath: directory.path),
            "\(directory.path) could not be listed — has SettingsFeature moved?"
        ).filter { $0.hasSuffix(".swift") }
        #expect(names.count > 5, "Only \(names.count) sources found in SettingsFeature. Suspicious.")
        return names
    }
}
