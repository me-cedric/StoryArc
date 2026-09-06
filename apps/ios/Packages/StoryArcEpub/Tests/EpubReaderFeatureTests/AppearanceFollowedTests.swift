import Foundation
import SwiftUI
import Testing

import Persistence
import StoryArcCore
@testable import EpubReaderFeature

/// The reading theme follows the device appearance while the book stays open.
///
/// `ebook-reader` / *Theme follows appearance* asks for the switch "then and there rather
/// than at the next open". Half of it was built: the opt-in exists and gates the answer. The
/// other half was not, because the answer was resolved **once**, at reader construction — so
/// a device that turned dark mid-chapter moved the chrome and left the page where it was.
///
/// Two rules are under test here and they are deliberately separate.
/// ``linkedPreset(for:in:)`` decides *whether* there is an answer at all: `nil` until the
/// reader links the two, which is the "with that setting off the reading theme is untouched"
/// clause. ``EpubReaderModel/follow(_:)`` decides what the reader does with one.
///
/// The reading position is **not** proved here, for the reason `ThemeAxisResetTests` records
/// at length: `currentLocation` is nil in this test host, so a before-and-after comparison
/// holds for any implementation, including one that moves the reader. What stands in its
/// place is the same tripwire that suite uses — the follow goes through `adopt`, which is the
/// one path that captures the locator, submits the preferences and goes back to the locator.
///
/// Android mirrors this suite in `AppearanceFollowedTest`.
@MainActor
@Suite("The reading theme follows the appearance mid-book")
struct AppearanceFollowedTests {

    /// A reader on a named preset, with the store it is given or none at all.
    private func reader(on preset: ThemePreset, preferences: ReaderPreferences? = nil) -> EpubReaderModel {
        let model = EpubReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: "/nowhere.epub"),
                format: .epub,
                displayTitle: "nowhere",
                origin: .embedded
            ),
            url: URL(fileURLWithPath: "/nowhere.epub"),
            preferences: preferences
        )
        model.adopt(preset)
        return model
    }

    // MARK: - Whether there is an answer at all

    @Test("The two are not linked until the reader links them")
    func theLinkIsOffUntilTheReaderAsksForIt() {
        let unlinked = AppSettings(appearance: .system)

        #expect(
            linkedPreset(for: unlinked, in: .dark) == nil,
            """
            A dark device dictated a reading theme to a reader who never asked for that. \
            `reading-themes` keeps appearance and reading theme apart by default, because a \
            dark chrome around a paper-white page is a preference rather than a mistake.
            """
        )
    }

    @Test("A linked preset follows the device rather than the literal choice")
    func theLinkFollowsTheDevice() {
        let linked = AppSettings(appearance: .system, linkReadingThemeToAppearance: true)

        #expect(linkedPreset(for: linked, in: .dark) == .quiet, "a dark device means the dark reading theme")
        #expect(linkedPreset(for: linked, in: .light) == .paper, "a light device means the light reading theme")
    }

    // MARK: - What the reader does with one

    @Test("A device that turns dark mid-book changes the page when the reader opted in")
    func darkMidBookChangesThePage() {
        let model = reader(on: .paper)

        model.follow(linkedPreset(for: AppSettings(appearance: .system, linkReadingThemeToAppearance: true), in: .dark))

        #expect(
            model.theme.preset == .quiet,
            """
            The page stayed light after the device turned dark. `ebook-reader`: the reading \
            theme switches "then and there rather than at the next open".
            """
        )
        #expect(
            model.values == ThemePreset.quiet.values,
            "the preset moved without its own typography, so the page is half of each theme"
        )
    }

    @Test("A device that turns dark mid-book leaves the page alone when the reader did not opt in")
    func darkMidBookLeavesAnUnlinkedPageAlone() {
        let model = reader(on: .paper)

        model.follow(linkedPreset(for: AppSettings(appearance: .system), in: .dark))

        #expect(
            model.theme.preset == .paper,
            """
            An unlinked reader lost their own reading theme to the device's night mode. \
            `ebook-reader`: "with that setting off the reading theme is untouched".
            """
        )
    }

    @Test("An appearance change that means the same preset leaves the reader's own changes alone")
    func thesamePresetLeavesTheReadersOwnChangesAlone() {
        let model = reader(on: .quiet)
        model.set(.lineSpacing, to: 2.4)

        // Dark and OLED Dark both mean Quiet. Re-adopting on that move would throw away
        // every axis the reader had moved, for a change that names the theme already on.
        model.follow(.quiet)

        #expect(
            model.values.lineHeight == 2.4,
            "an appearance change that names the theme already in force wiped the reader's own axes"
        )
        #expect(model.theme.isModified, "the deviation stopped being recorded as one")
    }

    @Test("The appearance's own theme is not recorded against the shelf")
    func theFollowedThemeIsNotRecorded() throws {
        let suite = "AppearanceFollowedTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReaderPreferences(defaults: defaults)

        let model = reader(on: .paper, preferences: preferences)
        let evening = ReaderPalette.derived(name: "Evening", background: "#F5EFE0")
        model.adoptColours(evening)

        model.follow(.quiet)

        let stored = preferences.themes().theme(for: EpubReaderModel.scope, shelf: model.shelf)
        #expect(
            stored.theme.custom == evening,
            """
            A sunset deleted the reader's own page colour. The device dictating a theme is \
            not the reader changing their mind, so it puts a theme in force without writing \
            it: `settings-and-about` keeps the shelf's own theme so that turning the setting \
            off again brings it back, and there is no other way back to a named slot.
            """
        )
        #expect(
            stored.theme.preset == .paper,
            """
            The device overwrote the shelf's stored preset. A reader who turns the link off \
            then gets the appearance's theme rather than their own, for ever.
            """
        )
    }

    // MARK: - The wiring, which no host test can watch

    @Test("The follow goes through the one path that preserves the reading position")
    func theFollowGoesThroughApplyTheme() throws {
        let source = try Self.source("LinkedPreset.swift")

        #expect(
            source.contains("applyTheme(remembering: false)"),
            """
            The follow no longer goes through `EpubReaderModel.applyTheme`. That is the path \
            a preset tap takes, and the only one that captures the locator, submits the \
            preferences and goes back to the locator afterwards. A theme written straight \
            onto `theme` would move the reader, and `reading-themes` asks for the position to \
            be preserved to the paragraph across the repagination.
            """
        )
    }

    @Test("The reader reads the link again while the book is open, rather than once on the way in")
    func theViewReadsTheLinkAgain() throws {
        let source = try Self.source("EpubReaderView.swift")

        #expect(
            source.contains(".onChange(of: linked)"),
            """
            The reader watches the appearance link no longer. A link read once is the \
            appearance the book happened to open in, so a device that turns dark mid-book is \
            seen at the next open and not before.
            """
        )
        #expect(
            source.contains("model.follow("),
            "the reader observes the link and does nothing with it, which is the same defect with a watcher"
        )
    }

    @Test("The appearance is resolved inside the view hierarchy, where it is live")
    func theViewResolvesTheAppearanceItself() throws {
        let source = try Self.source("EpubReaderView.swift")

        #expect(
            source.contains("@Environment(\\.colorScheme)"),
            """
            The colour scheme is read somewhere other than this view again. A `SwiftUI.App` \
            sits outside every view hierarchy and therefore outside every trait collection, \
            so a colour scheme read there holds its default and the whole link is inert.
            """
        )
        #expect(
            source.contains("linkedPreset(for: settings, in: colorScheme)"),
            "the view holds a colour scheme it never resolves the link with"
        )
    }

    /// One source file of the feature, read from disk.
    ///
    /// The package root is reached from `#filePath` rather than found: this repository nests
    /// agent worktrees at `.claude/worktrees/`, so a walk up looking for a marker leaves the
    /// checkout being compiled.
    private static func source(_ name: String) throws -> String {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: package.appending(path: "Sources/EpubReaderFeature/\(name)"),
            encoding: .utf8
        )
    }
}
