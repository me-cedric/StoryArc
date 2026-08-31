import Foundation
import Testing

internal import StoryArcCore

/// That the declutter did not remove a capability.
///
/// `comic-reader`, *Everything else is in the menu, and labelled*:
///
/// > **THEN** it offers the table of contents, bookmarks, search within the publication,
/// > reading themes and reader settings, each named in words rather than by icon alone
/// > **AND** every control that was reachable from the reader before this change is
/// > reachable from here in one action
///
/// **This is the test the change needed most.** Cutting eleven controls to two is easy; the
/// hard part is that nothing is lost doing it, and nothing in a compiler notices a row that
/// quietly stopped being drawn. `ReaderChromeTests` proves the chrome is small. This proves
/// the smallness cost nothing.
///
/// Two halves, and they fail for different reasons:
///
/// - **Labelled.** Every ``ReaderMenuEntry``'s key exists in both readers' catalogues, in
///   all four supported languages. `scripts/ios-strings.mjs` cannot see these keys — they
///   are built from `titleKey` rather than written as literals — so nothing else checks
///   them, and a missing one renders as `reader.menu.contents` on a shipped screen.
/// - **Reachable.** Each control the chrome used to draw is named somewhere in the menu's
///   own source.
///
/// **The second half reads source text, and it is a tripwire rather than a proof.** It says
/// the destination is spelled somewhere in the menu; it never says a row appeared or that
/// tapping it arrived. The honest test drives a booted simulator, and no gate in this
/// repository runs one — the same reason `ReaderRoutingWiringTests` and Android's
/// `ReaderChromeWiringTest` are written this way, and both carry the same warning.
@Suite("The menu keeps every capability the chrome had")
struct ReaderMenuTests {

    /// The package directory, from this test's own compiled path. See `ReaderChromeTests`
    /// for why this is `#filePath` and not a walk up from the working directory.
    private static let package: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static var epubPackage: URL {
        package.deletingLastPathComponent().appending(path: "StoryArcEpub")
    }

    /// Every file the comic reader's menu is built from.
    ///
    /// Three files rather than one: the rows, the settings controls, and the progress line.
    /// The menu is what they add up to, so the guard reads all three — a capability moved
    /// between them is still in the menu, and a capability deleted from all three is not.
    private static var comicMenu: [URL] {
        ["ReaderMenu.swift", "ReaderMenuSettings.swift", "ReaderMenuProgress.swift"].map {
            package.appending(path: "Sources/ReaderFeature/\($0)")
        }
    }

    private static var reflowableMenu: [URL] {
        ["EpubReaderMenu.swift", "EpubReaderProgress.swift"].map {
            epubPackage.appending(path: "Sources/EpubReaderFeature/\($0)")
        }
    }

    /// The two string catalogues, one per reader.
    private static var catalogues: [(reader: String, url: URL)] {
        [
            (
                "the comic reader",
                package.appending(path: "Sources/ReaderFeature/Resources/Localizable.xcstrings")
            ),
            (
                "the reflowable reader",
                epubPackage.appending(
                    path: "Sources/EpubReaderFeature/Resources/Localizable.xcstrings"
                )
            ),
        ]
    }

    /// The menu's code, with its prose removed, as one string.
    ///
    /// Comments are stripped first: this codebase explains itself at length, and a guard
    /// that found a destination named in a paragraph about that destination would be
    /// measuring the documentation.
    private func menuCode(_ urls: [URL]) throws -> String {
        var joined = ""
        for url in urls {
            let text = try #require(
                try? String(contentsOf: url, encoding: .utf8),
                "\(url.path) could not be read — has the reader's menu moved?"
            )
            joined += text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    guard let comment = line.range(of: "//") else { return String(line) }
                    return String(line[line.startIndex..<comment.lowerBound])
                }
                .joined(separator: "\n")
            joined += "\n"
        }
        return joined
    }

    /// One capability, and how the guard finds it.
    ///
    /// A named type rather than a tuple: three members is one past what `large_tuple`
    /// allows, and `capability.what` reads better than `capability.0` in a failure message.
    private struct Capability {
        let what: String
        let spelling: String
        /// The fewest occurrences that mean the row is *used* and not merely declared.
        ///
        /// Two where the entry is a view property of the menu's own: one occurrence is its
        /// declaration, so a row deleted from `settingsRows` while its body is left behind
        /// would still be spelled once.
        var atLeast = 1
    }

    /// What the comic reader's chrome could reach before this change, and the spelling that
    /// reaches it now.
    private static let comicCapabilities: [Capability] = [
        Capability(what: "the thumbnail browser", spelling: "isBrowsingThumbnails", atLeast: 2),
        Capability(what: "the PDF mark list", spelling: "openText(on: .marks)", atLeast: 1),
        Capability(
            what: "search inside the publication",
            spelling: "openText(on: .search)",
            atLeast: 1
        ),
        Capability(what: "the PDF outline", spelling: "findingTab = .contents", atLeast: 1),
        Capability(what: "the image adjustments", spelling: "isAdjusting = true", atLeast: 1),
        Capability(what: "the chapter neighbours", spelling: "chapterRow", atLeast: 1),
        Capability(what: "the page slider", spelling: "pageSliderRow", atLeast: 1),
        Capability(what: "the page-transition choice", spelling: "transitionRow", atLeast: 2),
        Capability(what: "the page-fit choice", spelling: "fitRow", atLeast: 2),
        Capability(what: "the reading-direction choice", spelling: "directionRow", atLeast: 2),
        Capability(what: "the spread offset", spelling: "spreadOffsetBinding", atLeast: 2),
        Capability(
            what: "the continuous-scroll separator",
            spelling: "separatorBinding",
            atLeast: 2
        ),
        Capability(what: "the skipped-page count", spelling: "skippedPageCount", atLeast: 1),
    ]

    /// The same, for the reflowable reader.
    private static let reflowableCapabilities: [Capability] = [
        Capability(
            what: "the table of contents",
            spelling: "openContents(on: .contents)",
            atLeast: 1
        ),
        Capability(what: "the bookmark list", spelling: "openContents(on: .bookmarks)", atLeast: 1),
        Capability(what: "marking this position", spelling: "toggleBookmark", atLeast: 1),
        Capability(
            what: "search inside the book",
            spelling: "openContents(on: .search)",
            atLeast: 1
        ),
        Capability(
            what: "highlights and notes",
            spelling: "openContents(on: .annotations)",
            atLeast: 1
        ),
        Capability(what: "the reading themes", spelling: "isShowingTheme = true", atLeast: 1),
        Capability(what: "starting read-aloud", spelling: "startReadAloud", atLeast: 1),
        Capability(what: "stopping read-aloud", spelling: "stopReadAloud", atLeast: 1),
        Capability(what: "the progress line", spelling: "progression", atLeast: 1),
    ]

    /// How many times `needle` appears in `haystack`.
    private func count(of needle: String, in haystack: String) -> Int {
        haystack.ranges(of: needle).count
    }

    private func expectReachable(
        _ capabilities: [Capability],
        in urls: [URL],
        reader: String
    ) throws {
        let code = try menuCode(urls)
        for capability in capabilities {
            let found = count(of: capability.spelling, in: code)
            #expect(
                found >= capability.atLeast,
                """
                \(reader)'s menu no longer reaches \(capability.what) — \
                `\(capability.spelling)` appears \(found) time(s) in its source and \
                \(capability.atLeast) was the floor. `comic-reader` requires every control \
                that was reachable from the reader before the declutter to stay reachable \
                from the menu in one action. Cutting eleven controls to two is only correct \
                if nothing was lost doing it.
                """
            )
        }
    }

    @Test("The comic reader's menu reaches everything its eleven icons did")
    func comicMenuKeepsEverything() throws {
        try expectReachable(Self.comicCapabilities, in: Self.comicMenu, reader: "The comic reader")
    }

    @Test("The reflowable reader's menu reaches everything its five pills did")
    func reflowableMenuKeepsEverything() throws {
        try expectReachable(
            Self.reflowableCapabilities,
            in: Self.reflowableMenu,
            reader: "The reflowable reader"
        )
    }

    @Test("Every menu row is named in words, in all four languages, in both readers")
    func everyRowIsLabelled() throws {
        for catalogue in Self.catalogues {
            let data = try #require(
                try? Data(contentsOf: catalogue.url),
                "\(catalogue.url.path) could not be read — has the catalogue moved?"
            )
            let parsed = try #require(
                try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                "\(catalogue.url.path) is not a string catalogue this test can read."
            )
            let strings = try #require(parsed["strings"] as? [String: Any])

            for entry in ReaderMenuEntry.allCases {
                let record = strings[entry.titleKey] as? [String: Any]
                #expect(
                    record != nil,
                    """
                    \(catalogue.reader)'s catalogue has no `\(entry.titleKey)`. The menu \
                    builds its rows from `ReaderMenuEntry.titleKey`, which \
                    `scripts/ios-strings.mjs` cannot see — so a missing key is not a build \
                    failure, it is the key itself rendered on the row. `comic-reader` \
                    requires each row "named in words rather than by icon alone".
                    """
                )
                let localizations = record?["localizations"] as? [String: Any] ?? [:]
                for language in ["en", "de", "es", "fr"] {
                    #expect(
                        localizations[language] != nil,
                        """
                        \(catalogue.reader)'s `\(entry.titleKey)` has no \(language) \
                        translation. `localization` requires a build that fails "if any \
                        supported language is missing a key that English defines".
                        """
                    )
                }
            }
        }
    }
}
