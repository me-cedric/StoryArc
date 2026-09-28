import Foundation
import Testing

/// The home-screen menu and the reading activity, which are the platform half of two scenarios.
///
/// ``QuickActionsTests`` owns the *list* — which entries the menu holds, in which order — and
/// Android's `QuickActionsTest` asserts the same table. This suite owns what iOS then does with
/// that list, and until now nothing did: `App/HomeScreenQuickActions.swift` and
/// `App/ReadingContinuity.swift` had no test of any kind on the host.
///
/// **Two kinds of assertion, and they are not equally strong.** The names are read out of the
/// app's own string catalogue and are values: a language that loses an entry fails here by name.
/// Everything else reads source text, for the reason ``CarSceneWiringTests`` records —
/// `apps/ios/project.yml` declares no app unit-test target, so nothing in this package can
/// construct a shortcut item, a scene delegate or an `NSUserActivity`. Those are tripwires: they
/// assert the wiring is written, never that a launcher drew a menu.
/// `apps/ios/UITests/ReadingContinuityUITests.swift` is the device half.
///
/// `native-experience`, *Home-screen quick actions*: the entries "survive the app being killed,
/// because the system stores them rather than the app", and "every entry is localised in each
/// supported language". *Continuity*: iOS "publishes it as a user activity, so the reader's
/// other devices offer to continue it and the publication appears in Spotlight".
@Suite("Quick action and continuity wiring")
struct QuickActionWiringTests {

    /// `apps/ios`, from this file rather than the working directory: this repository nests
    /// worktrees at `.claude/worktrees/<name>/`, and a walk that climbs out validates the
    /// parent checkout instead of the one under test.
    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/StoryArcCoreTests/this file → apps/ios
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

    /// Runs of whitespace collapsed to one space, so a match on source text survives a
    /// reformat that changes indentation without changing meaning.
    private func normalizedWhitespace(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: The menu

    /// The menu lives in the system's store, which is why it outlives the process.
    ///
    /// The scenario states the consequence rather than the call: "the entries survive the app
    /// being killed, because the system stores them rather than the app". `shortcutItems` is
    /// written into the app's own state and read by SpringBoard whether or not a process
    /// exists; a list held in a preference of the app's own would not be.
    @Test("The menu is handed to the system rather than kept by the app")
    func theSystemHoldsTheMenu() throws {
        let actions = try source("App/HomeScreenQuickActions.swift")

        #expect(
            actions.contains("UIApplication.shared.shortcutItems ="),
            """
            the menu is no longer written to `UIApplication.shortcutItems`, so nothing the \
            launcher reads is being set and the entries die with the process
            """
        )
    }

    /// Every entry is filed under the identifier both platforms store.
    ///
    /// ``QuickAction/id`` is the one part of this the two platforms share rather than mirror: a
    /// menu already on a reader's home screen carries it. An entry filed under a literal here
    /// would be an entry the app could not read back.
    @Test("Each entry is filed under the shared identifier")
    func entriesAreFiledUnderTheSharedIdentifier() throws {
        let actions = try source("App/HomeScreenQuickActions.swift")
        let items = actions.components(separatedBy: "UIApplicationShortcutItem(").dropFirst()

        #expect(items.count == 3, "there are no longer three entries built in this file")
        for item in items {
            #expect(
                normalizedWhitespace(item).hasPrefix("type: action.id,"),
                "an entry is filed under something other than the identifier both platforms store"
            )
        }
    }

    /// The continue entry carries the publication's key, not the file it was last seen at.
    ///
    /// "A menu can be older than the scan that last placed the file" — the file's own words.
    /// The key survives a move; a path does not.
    @Test("The continue entry carries an identifier the library can be asked for")
    func theContinueEntryCarriesAnIdentifier() throws {
        let actions = try source("App/HomeScreenQuickActions.swift")

        #expect(
            actions.contains("userInfo: [publicationKey: id as NSString]"),
            "the continue entry no longer carries the publication's identifier"
        )
        #expect(
            normalizedWhitespace(actions).contains("QuickActionRequest( id: item.type,")
                && actions.contains("publicationID: item.userInfo?[publicationKey] as? String"),
            """
            the entry is no longer read back through the key it was written under, so \
            publishing and handling have stopped agreeing
            """
        )
    }

    /// Every entry is named in every language the app ships.
    ///
    /// The key is read out of the source and the answer out of the catalogue, so this fails
    /// both ways: an entry that stops looking a name up, and a language that stops answering.
    @Test(
        "Each entry is named in all four languages",
        arguments: ["shortcut.continue", "shortcut.library", "shortcut.downloads"]
    )
    func eachEntryIsNamedInEveryLanguage(key: String) throws {
        let actions = try source("App/HomeScreenQuickActions.swift")
        #expect(
            actions.contains("String(localized: \"\(key)\", bundle: .main, locale: .storyArc)"),
            "no entry looks up `\(key)`, so one of the three is drawn with a raw key or nothing"
        )

        let record = try #require(
            try Self.appCatalogue[key] as? [String: Any],
            "the app's string catalogue does not answer `\(key)`"
        )
        let localizations = try #require(
            record["localizations"] as? [String: Any],
            "`\(key)` is in the catalogue with no translations at all"
        )
        for language in ["en", "fr", "de", "es"] {
            #expect(
                localizations[language] != nil,
                "`\(key)` has no \(language) translation, so that reader gets the English word"
            )
        }
    }

    /// A cold launch and a running app reach the same inbox.
    ///
    /// The two moments are on opposite sides of the app — a cold launch reaches the scene
    /// before SwiftUI has built anything — and only one of them was ever wired at a time
    /// while this was being written. Both are asserted, because either alone looks finished.
    @Test("A quick action arrives on a cold launch and on a running app alike")
    func bothArrivalsReachTheInbox() throws {
        let actions = try source("App/HomeScreenQuickActions.swift")

        #expect(
            actions.contains("connectionOptions.shortcutItem"),
            "a cold launch's quick action is dropped: nothing reads the connection options"
        )
        #expect(
            actions.contains("performActionFor shortcutItem: UIApplicationShortcutItem"),
            "a tap on a running app is dropped: the scene handles no action"
        )
        #expect(
            actions.components(separatedBy: "QuickActionInbox.shared.receive(").count == 3,
            "the two arrivals no longer end up in the same inbox"
        )
    }

    /// And the scene delegate is installed, because SwiftUI surfaces neither callback.
    @Test("The scene delegate is installed on the phone's scene")
    func theSceneDelegateIsInstalled() throws {
        let orientation = try source("App/OrientationDelegate.swift")

        #expect(
            orientation.contains("configurationForConnecting"),
            "nothing configures the connecting scene, so no delegate of ours is ever installed"
        )
        #expect(
            orientation.contains("QuickActionSceneDelegate.self"),
            "the phone's scene no longer gets the delegate that receives a quick action"
        )
    }

    // MARK: Continuity

    /// One activity does both jobs, and it is offered to both.
    ///
    /// Handoff and Spotlight describe the same fact — this person is reading this book — and
    /// the two flags are set on one activity so they cannot drift. A test of one would pass
    /// with the other deleted, which is why both are named here.
    @Test("The reading activity is offered to Handoff and to Spotlight")
    func theActivityIsOfferedToBoth() throws {
        let continuity = try source("App/ReadingContinuity.swift")

        #expect(
            continuity.contains("activity.isEligibleForHandoff = true"),
            "the activity is no longer offered to the reader's other devices"
        )
        #expect(
            continuity.contains("activity.isEligibleForSearch = true"),
            "the publication no longer appears in Spotlight"
        )
        #expect(
            continuity.contains("activity.persistentIdentifier = publication.id"),
            """
            the activity has no persistent identifier, so every launch indexes the same book \
            again and a later deletion has no handle to use
            """
        )
    }

    /// It carries an identifier, and nothing else leaves the device.
    ///
    /// "A path is true on one device and means nothing on another." The receiving device is
    /// told which publication and looks in its own library; there is no backend and this does
    /// not invent one.
    @Test("The activity carries an identifier rather than a position or a path")
    func theActivityCarriesAnIdentifier() throws {
        let continuity = try source("App/ReadingContinuity.swift")

        #expect(
            continuity.contains("activity.userInfo = [publicationKey: publication.id]"),
            "the activity no longer carries the publication's identifier"
        )
        #expect(
            continuity.contains("activity.requiredUserInfoKeys = [publicationKey]"),
            """
            the key is no longer required, so an activity arriving without it is handed over \
            as though it named a book
            """
        )
    }

    /// A publication the library cannot place lands on the library rather than on an error.
    ///
    /// The wait is bounded on purpose: a quick action or a handover can land on a cold launch
    /// with an empty shelf, and giving up is part of the behaviour rather than a failure of
    /// it. What must not happen is an error screen, or a reader thrown into a book minutes
    /// after they asked for it.
    @Test("A publication that cannot be placed is given up on, not errored over")
    func anUnplaceablePublicationIsGivenUpOn() throws {
        let continuity = try source("App/ReadingContinuity.swift")
        let opened = try #require(
            continuity.range(of: "private func settle() async {"),
            "`settle()` is gone — this is where the wait for the library lives"
        )
        // To the method's own closing brace, which is the first one at its indentation.
        let settle = String(continuity[opened.upperBound...]).components(separatedBy: "\n    }")[0]

        #expect(
            settle.contains("for _ in 0 ..< Self.attempts"),
            "the wait for the library is no longer bounded, so a cold launch can wait forever"
        )
        #expect(
            continuity.components(separatedBy: "onOpen(").count == 2,
            "something other than the settled lookup opens a publication"
        )
    }

    // MARK: The app's own string catalogue

    private static var appCatalogue: [String: Any] {
        get throws {
            let url = appleRoot.appending(path: "App/Resources/Localizable.xcstrings")
            let data = try #require(
                try? Data(contentsOf: url),
                "the app's string catalogue is not readable at \(url.path)"
            )
            let parsed = try #require(
                try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                "the app's string catalogue at \(url.path) is not valid JSON"
            )
            return try #require(
                parsed["strings"] as? [String: Any],
                "the app's string catalogue at \(url.path) has no `strings` table"
            )
        }
    }
}
