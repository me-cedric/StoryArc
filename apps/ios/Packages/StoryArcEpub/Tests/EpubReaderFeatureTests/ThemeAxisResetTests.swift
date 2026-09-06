import Foundation
import Testing

import Persistence
import StoryArcCore
@testable import EpubReaderFeature

/// That a gesture on one axis slider puts that axis back to the preset's value.
///
/// `reading-themes`, *Resetting an axis*:
///
/// > **WHEN** a user long-presses or double-taps a slider
/// > **THEN** that axis returns to its preset value
///
/// The axes were built and this gesture was not, on either platform, while the task list
/// said it was. Two of these cases carry the weight: the reset must touch **one** axis, and
/// it must be reachable without the gesture. A reset that quietly restores everything is a
/// worse defect than no reset, and a gesture with no accessible equivalent breaks
/// `native-experience`'s rule that a control announces what it does.
///
/// Android mirrors this suite in `ThemeAxisResetTest`.
@MainActor
@Suite("A gesture resets one axis")
struct ThemeAxisResetTests {

    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(
                atPath: candidate.appending(path: "manifest.json").path
            ) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    private func model(preferences: ReaderPreferences? = nil) -> EpubReaderModel {
        let url = Self.corpus.appending(path: "ebooks/fixture.epub")
        return EpubReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: url.path),
                format: .epub,
                displayTitle: "fixture.epub",
                origin: .embedded
            ),
            url: url,
            preferences: preferences
        )
    }

    @Test("The gesture returns the axis to the preset's own value")
    func theAxisReturns() {
        let reader = model()
        reader.adopt(.calm)
        reader.set(.lineSpacing, to: 2.4)
        #expect(reader.values.lineHeight == 2.4, "the drag moved the axis")

        ThemeAxesSheet.reset(.lineSpacing, on: reader)

        #expect(
            reader.values.lineHeight == ThemePreset.calm.values.lineHeight,
            """
            The reset left the axis where the reader had dragged it. `reading-themes`: \
            "that axis returns to its preset value".
            """
        )
    }

    @Test("It returns that axis alone, and leaves every other one where the reader put it")
    func onlyThatAxisReturns() {
        let reader = model()
        reader.adopt(.calm)
        reader.set(.lineSpacing, to: 2.4)
        reader.set(.margins, to: 2.1)
        reader.set(.wordSpacing, to: 0.3)

        ThemeAxesSheet.reset(.lineSpacing, on: reader)

        #expect(reader.values.lineHeight == ThemePreset.calm.values.lineHeight)
        #expect(
            reader.values.pageMargins == 2.1 && reader.values.wordSpacing == 0.3,
            """
            Resetting one axis moved another. This is the worst form the defect takes: a \
            reader who nudges the margins, then puts the line spacing back, must keep the \
            margins. `reading-themes` scopes the gesture to "that axis".
            """
        )
    }

    @Test("Resetting the only moved axis leaves the preset unmodified")
    func theResetClearsTheDeviation() {
        let reader = model()
        reader.adopt(.calm)
        reader.set(.lineSpacing, to: 2.4)
        #expect(reader.theme.isModified, "the drag marked the preset modified")

        ThemeAxesSheet.reset(.lineSpacing, on: reader)

        #expect(
            !reader.theme.isModified,
            """
            The reset put the axis back and still recorded it as a deviation. Calm keeps the \
            "Modified" caption and the whole-theme "Restore Calm" action stays on screen with \
            nothing left to restore. `reading-themes`, *Resetting the preset that is already \
            unmodified*: the action is "absent rather than present and doing nothing, because \
            a control that never changes anything teaches a reader to distrust the ones that \
            do".
            """
        )
    }

    @Test("Resetting one axis leaves the other moved axis marked as deviating")
    func theResetKeepsTheOtherDeviations() {
        let reader = model()
        reader.adopt(.calm)
        reader.set(.lineSpacing, to: 2.4)
        reader.set(.margins, to: 2.1)

        ThemeAxesSheet.reset(.lineSpacing, on: reader)

        #expect(
            reader.theme.deviations == [.margins],
            """
            The reset changed the deviations of an axis it was not asked for. Only the axis \
            that went back to the preset's value stops deviating; the margins the reader \
            nudged still differ from Calm, so Calm is still modified and still restorable.
            """
        )
    }

    @Test("The reset reaches the stored theme, not only the slider")
    func theResetIsRemembered() throws {
        let suite = "ThemeAxisResetTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ReaderPreferences(defaults: defaults)

        let reader = model(preferences: preferences)
        reader.adopt(.calm)
        reader.set(.lineSpacing, to: 2.4)

        ThemeAxesSheet.reset(.lineSpacing, on: reader)

        let stored = preferences.themes().theme(for: EpubReaderModel.scope, shelf: reader.shelf)
        #expect(
            stored.values.lineHeight == ThemePreset.calm.values.lineHeight,
            """
            The reset changed the slider and not the shelf's stored theme, so the next book \
            on this shelf opens with the value the reader reset away from. The preview reads \
            the same `values` the assertion above reads, so this is the half a view cannot \
            show.
            """
        )
    }

    /// The reading position is **not** proved here, and this is what stands in its place.
    ///
    /// The case that used to sit here compared `String(describing:
    /// navigator?.currentLocation)` before the reset and after it. `currentLocation` is nil
    /// in this test host, because the navigator is never laid out in a window, so both
    /// sides read "nil" and the case held for any implementation — including one that moved
    /// the reader. Worse, `EpubReaderModel.applyTheme` takes the other branch under a nil
    /// location: `guard let locator else { return }` returns before the restore the case
    /// named. Its only guard was `#require(navigator != nil)`, which is the navigator
    /// object rather than a position.
    ///
    /// So this reads the three statements that do the work and pins their order. It is a
    /// tripwire, like the three below it, and it fails when the capture, the submit or the
    /// return is removed or reordered. It says nothing about a real reader. Task 3.5 in
    /// `reader-theming-and-page-transitions` records the guarantee as unproved on both
    /// platforms, and names what a proof would need.
    @Test("The reflow is bracketed by capturing the position and going back to it")
    func theReflowIsBracketedByTheLocator() throws {
        let source = try Self.source("EpubReaderModel.swift")

        let capture = try #require(source.range(of: "let locator = navigator.currentLocation"))
        let submit = try #require(source.range(of: "navigator.submitPreferences("))
        let restore = try #require(source.range(of: "await navigator.go(to: locator"))

        #expect(
            capture.upperBound < submit.lowerBound && submit.upperBound < restore.lowerBound,
            """
            `applyTheme` no longer captures the reading position, submits the preferences \
            and goes back to that position, in that order. `reading-themes`: the position \
            "is preserved to the paragraph across the repagination, exactly as a type-size \
            change is". Submitting first loses the paragraph, because Readium lands on the \
            progression rather than on the paragraph.
            """
        )
    }

    @Test("The reset goes through the one path that preserves the reading position")
    func theResetGoesThroughApplyTheme() throws {
        let sliders = try Self.source("ThemeAxisSliders.swift")

        #expect(
            sliders.contains("model.set(axis, to: model.theme.preset.values.value(of: axis))"),
            """
            The reset no longer goes through `EpubReaderModel.set`. That is the path a drag \
            takes, and the only one that captures the locator, submits the preferences and \
            goes back to the locator afterwards. A reset written straight onto `values` \
            would move the reader.
            """
        )
    }

    @Test("The gesture is a long press on the slider itself")
    func theGestureIsALongPress() throws {
        let sliders = try Self.source("ThemeAxisSliders.swift")

        #expect(
            sliders.contains("LongPressGesture()"),
            """
            No long press is attached to the axis slider. `reading-themes` asks for a long \
            press or a double tap, and a long press on a control is the iOS idiom.
            """
        )
    }

    @Test("An accessibility action performs the same reset, named from the catalogue")
    func theActionIsReachableWithoutTheGesture() throws {
        let sliders = try Self.source("ThemeAxisSliders.swift")

        #expect(
            sliders.contains(#".accessibilityAction(named: Text("theme.axis.reset", bundle: .module))"#),
            """
            The axis slider carries no accessibility action, so the reset is reachable only \
            by a gesture. VoiceOver, Switch Control and a keyboard cannot perform one. \
            `native-experience` requires every control to announce what it does.
            """
        )
    }

    @Test(
        "The action's name is translated in every supported language",
        arguments: ["en", "fr", "de", "es"]
    )
    func theActionNameIsTranslated(language: String) throws {
        let url = Self.package
            .appending(path: "Sources/EpubReaderFeature/Resources/Localizable.xcstrings")
        let catalogue = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let strings = (catalogue as? [String: Any])?["strings"] as? [String: Any]
        let entry = strings?["theme.axis.reset"] as? [String: Any]
        let localizations = entry?["localizations"] as? [String: Any]
        let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]

        #expect(
            (unit?["value"] as? String)?.isEmpty == false,
            """
            `theme.axis.reset` has no value in this language. Every sentence the app draws \
            is catalogued in en, fr, de and es, and an accessibility action a reader cannot \
            read is not an accessible equivalent.
            """
        )
    }

    /// This package's directory, walked up from this file.
    private static let package: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// One source file of the feature, read from disk.
    ///
    /// A tripwire rather than a proof, for the reason `ThemeSheetTests` gives: no host test
    /// can press a SwiftUI gesture, so the assertions above say the wiring is written and
    /// never that a finger reached it. The behaviour they guard is proved over the model.
    private static func source(_ name: String) throws -> String {
        try String(contentsOf: package.appending(path: "Sources/EpubReaderFeature/\(name)"),
                   encoding: .utf8)
    }
}
