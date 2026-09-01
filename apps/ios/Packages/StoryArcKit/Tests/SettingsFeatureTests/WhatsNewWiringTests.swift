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
/// `ShellWiringTests` sets out: the app target has no test target, and `swift test` runs on the
/// host with no simulator so a `TabView` cannot be composed here.
///
/// **The deletion condition this comment used to offer rested on a false premise.** It said the
/// simulator UI test was one "which no gate runs", and offered to be deleted the day that run
/// became a gate. `.github/workflows/ios.yml` has run `-only-testing:StoryArcUITests` against a
/// booted iPhone 17 Pro since `4f8c4f1b`, on 2026-08-27 — before this file was written. So the
/// condition was already met when it was offered, and the file was not deleted, which is the
/// right outcome for the wrong reason.
///
/// What the gated run actually catches here is narrower than the condition assumed.
/// `ScreenshotTests.testCaptureWhatsNew` injects an older seen version and waits for
/// `Continue`, so deleting the `.sheet` from `AppShell` **would** fail it. Handing
/// ``WhatsNewHistory`` a store would not: nothing on a screen changes when About writes a flag.
/// That second assertion is this file's alone, and the first is worth keeping as the cheap
/// half — a host suite that names the line beats a simulator run that names a missing button.
///
/// It is a tripwire, not a proof. It asserts a presentation is declared and a store is absent;
/// it never asserts a sheet appeared.
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

    /// Nothing about what changed is fetched.
    ///
    /// `settings-and-about`'s *An update installed while offline*: "the screen appears in full,
    /// because what changed ships with the app and is never fetched". Both sources say so at
    /// length in prose, and both are correct by construction — the log is a compiled value and
    /// the sheet draws it.
    ///
    /// **And nothing would have failed if somebody added a fetch.** A re-verification greppped
    /// these two files for network symbols and found matches only inside doc comments; the
    /// requirement was true and asserted by nothing, which is the state a structural claim
    /// decays from. This is the assertion. It is why the scenario is not merely "correct by
    /// construction" but held.
    ///
    /// Comment lines are stripped before the search, and that is what makes the test possible:
    /// both files use the words *fetched* and *URL* to explain why there is no fetch and no
    /// URL, so a naive search of the whole text fails on the prose that documents the rule it
    /// guards. `ShellWiringTests` and ``theDecisionIsTakenOnce`` above both record falling into
    /// the same trap.
    @Test("What changed is never fetched, on either screen")
    func nothingIsFetched() throws {
        for file in ["WhatsNew.swift", "WhatsNewSheet.swift"] {
            let code = try Self.codeOnly(
                in: try source("Packages/StoryArcKit/Sources/SettingsFeature/\(file)")
            )
            for symbol in Self.networkSymbols {
                #expect(
                    !code.contains(symbol),
                    """
                    \(file) names \(symbol) in code rather than in prose.
                    `settings-and-about` promises what changed "ships with the app and is never
                    fetched" — the screen a reader sees on the launch after an update, which may
                    well be the launch where they have no network at all.
                    """
                )
            }
        }
    }

    /// Anything that could reach the network from a Swift file in this module.
    ///
    /// Not exhaustive and not meant to be: it is every way this codebase actually reaches a
    /// server, plus the two Foundation types anything new would be built out of.
    private static let networkSymbols = [
        "URLSession",
        "URLRequest",
        "URLComponents",
        "URL(string:",
        "dataTask",
        "NWConnection",
        "NWPathMonitor",
        "http://",
        "https://",
    ]

    /// A source's text with every comment line removed.
    ///
    /// Line comments and block-comment bodies both go. Crude — a trailing comment on a line of
    /// code survives, and a string literal holding `//` would be cut — and that is the right
    /// direction to be crude in: this is a negative assertion, so keeping too much code fails
    /// loudly and keeping too little would pass quietly.
    private static func codeOnly(in text: String) -> String {
        var inBlock = false
        var kept: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if inBlock {
                if line.contains("*/") { inBlock = false }
                continue
            }
            if line.hasPrefix("/*") {
                if !line.contains("*/") { inBlock = true }
                continue
            }
            if line.hasPrefix("//") || line.hasPrefix("*") { continue }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
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
