import Foundation
import Testing

import StoryArcCore

/// Nothing but the platform records which icon is in use.
///
/// `native-experience`'s *The platform is the only record*: the app "asks the platform rather
/// than a preference of its own, so there is no second record that can disagree", and
/// "nothing about the choice is written to preferences, a backup, a log or a diagnostic".
/// `AppIconChoice`'s own note says the same — "there is deliberately no entry for this in
/// `AppSettings`" — and `brand-identity-and-app-icons` was archived with nothing asserting it.
///
/// **This reads source text**, for the reason `ArcStopsAreNotChromeTests` does: the rule is
/// about where a name appears, and that is exactly what a compiler cannot object to. A stored
/// property of type `AppIconChoice` on `AppSettings` type-checks; a `UserDefaults` write in the
/// store type-checks; a `[Settings]` line in the diagnostic type-checks. Each is one line, and
/// each is what this fails on. Android's `AppIconChoiceIsNotRecordedTest` is the mirror and
/// enforces the same table over its own tree, so each platform's own gate catches its own
/// violation.
///
/// The type is **named and referenced**: `AppIconChoice.allCases` below is what makes a rename
/// of the type break this file's compile rather than leave it searching for a name nothing
/// uses any more — the vacuity `ArcStopsAreNotChromeTests` guards against the same way.
@Suite("Nothing but the platform records the icon choice")
struct AppIconChoiceIsNotRecordedTests {

    /// The three files allowed to name the choice: the faces, the store that asks the platform,
    /// and the chooser that draws the answer. Everything else in the app has no business with it.
    private static let holders: Set<String> = ["AppIconChoice.swift", "AppIconStore.swift", "AppIconSettings.swift"]

    /// Words that reach a preference, a file or a log. None belongs in the two files that own
    /// the choice: the store asks `UIApplication` and the chooser asks the store.
    private static let storageWords = [
        "UserDefaults", "AppStorage", "SceneStorage", "import Persistence", "FileManager", "Logger", "os_log", "print(",
    ]

    /// `#filePath` and not a walk up from the working directory, for the reason
    /// `ArcStopsAreNotChromeTests` gives: agent worktrees nest under `.claude/worktrees/`, and
    /// a walk that climbs leaves the checkout under test.
    private static let kit: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DesignSystemTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // StoryArcKit

    private static let roots: [URL] = {
        let packages = kit.deletingLastPathComponent()
        let ios = packages.deletingLastPathComponent()
        return [
            kit.appending(path: "Sources"),
            packages.appending(path: "StoryArcEpub/Sources"),
            ios.appending(path: "App"),
        ]
    }()

    private static let settings = kit.appending(path: "Sources/StoryArcCore/AppSettings.swift")
    private static let diagnostic = kit.appending(path: "Sources/SettingsFeature/Diagnostic.swift")
    private static let persistence = kit.appending(path: "Sources/Persistence")

    private static func swiftFiles(in root: URL) -> [URL] {
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return walk.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .filter { !$0.pathComponents.contains("Generated") }
    }

    /// A file's code, with `/* */` blocks and `//` tails removed.
    ///
    /// Every file this reads explains in prose why the choice is *not* stored, and names the
    /// stores it does not reach in order to say so. A guard that read the prose would fail on
    /// the documentation of the rule.
    private static func code(of file: URL) -> String {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return "" }
        let withoutBlocks = text.replacing(/\/\*.*?\*\//.dotMatchesNewlines(), with: "")
        return withoutBlocks
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// The lines of `file`'s code that mention `word`, case-insensitively, numbered for the report.
    private static func lines(mentioning word: String, in file: URL) -> [String] {
        code(of: file)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .filter { $0.element.localizedCaseInsensitiveContains(word) }
            .map { "\(file.lastPathComponent):\($0.offset + 1)" }
    }

    @Test("The walk reaches every root and the three files a record could hide in")
    func theWalkCoversWhatItClaims() {
        for root in Self.roots {
            #expect(Self.swiftFiles(in: root).count >= 10, "almost no Swift under \(root.path) — has the layout moved?")
        }
        #expect(Self.roots.count == 3, "a root was added or dropped without a floor for it")
        #expect(FileManager.default.fileExists(atPath: Self.settings.path), "AppSettings.swift has moved")
        #expect(FileManager.default.fileExists(atPath: Self.diagnostic.path), "Diagnostic.swift has moved")
        #expect(Self.swiftFiles(in: Self.persistence).count >= 10, "almost no stores under Persistence — has it moved?")
    }

    @Test("Only the faces, the store and the chooser name the choice")
    func onlyTheChooserNamesTheChoice() {
        // The reference. Five faces is `AppIconChoiceTests`' claim; here it only has to compile.
        #expect(AppIconChoice.allCases.count == 5)

        var offenders: [String] = []
        var holdersSeen: Set<String> = []
        for file in Self.roots.flatMap(Self.swiftFiles(in:)) {
            let names = Self.code(of: file).contains("AppIconChoice")
            if Self.holders.contains(file.lastPathComponent) {
                if names { holdersSeen.insert(file.lastPathComponent) }
            } else if names {
                offenders.append(file.lastPathComponent)
            }
        }

        #expect(
            offenders.isEmpty,
            """
            These name `AppIconChoice` outside the three files that own it: \(offenders.joined(separator: ", ")).
            The platform is the only record of which icon is in use. A screen that needs the face
            asks `AppIconStore`; nothing stores, logs or reports it.
            """
        )
        // Non-vacuous: the three holders exist and do name it, so a rename cannot pass by absence.
        #expect(
            holdersSeen == Self.holders,
            "expected \(Self.holders.sorted()) to name the choice, found \(holdersSeen.sorted())"
        )
    }

    @Test("AppSettings holds no icon field")
    func appSettingsHoldsNoIcon() {
        let hits = Self.lines(mentioning: "icon", in: Self.settings)
        #expect(
            hits.isEmpty,
            "AppSettings names the icon at \(hits) — a stored choice is a second record that can disagree"
        )
    }

    @Test("No preference key names the icon")
    func noPreferenceKeyNamesTheIcon() {
        let hits = Self.swiftFiles(in: Self.persistence).flatMap { Self.lines(mentioning: "icon", in: $0) }
        #expect(hits.isEmpty, "a store names the icon at \(hits) — iOS persists `alternateIconName` itself")
    }

    @Test("The diagnostic says nothing about the icon")
    func theDiagnosticSaysNothingAboutTheIcon() {
        let hits = Self.lines(mentioning: "icon", in: Self.diagnostic)
        #expect(hits.isEmpty, "the diagnostic names the icon at \(hits) — nothing about the choice goes into a report")
    }

    @Test("The store and the chooser reach no preference, file or log")
    func theChooserReachesNoStore() {
        let owners = ["Sources/SettingsFeature/AppIconStore.swift", "Sources/SettingsFeature/AppIconSettings.swift"]
        var offenders: [String] = []
        for path in owners {
            let file = Self.kit.appending(path: path)
            let code = Self.code(of: file)
            #expect(!code.isEmpty, "\(path) is empty or has moved")
            for word in Self.storageWords where code.contains(word) {
                offenders.append("\(file.lastPathComponent) — \(word)")
            }
        }
        #expect(offenders.isEmpty, "the icon's owners reach storage or a log: \(offenders)")
    }
}
