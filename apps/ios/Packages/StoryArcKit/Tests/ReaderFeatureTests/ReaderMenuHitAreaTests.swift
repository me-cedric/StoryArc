import Foundation
import Testing

/// Every settings row in the reader's menu opens from anywhere on the row.
///
/// **Established on a booted iPhone 17 Pro, by hand, because the sweep asked for a finger
/// before this was called a defect.** `SweepComicReaderTests.testCaptureComicFitPicker`
/// tapped the *Fit* row and photographed a sheet that had not changed, twice, in the light
/// and the dark run, while *Transition* directly above it opened its menu from the same
/// lookup and the same tap. Three taps on the device settle it:
///
/// - on the trailing value, `Screen ⌄` — the picker opens, with all four options;
/// - on the middle of the row — **nothing**;
/// - on the word *Fit* itself — **nothing**.
///
/// So the control works and the row does not, which is the worst of the three possible
/// answers: a reader who taps the name of the setting they want to change gets no feedback at
/// all, and the row beside it — same section, same shape, same trailing value — opens from its
/// label. `Transition` is a `Menu`, whose label *is* the button and therefore fills the row;
/// `Fit` and `Reading direction` were `Picker`s, and a menu-styled picker's button is the
/// trailing value alone.
///
/// The test's tap was not the artefact. `XCUIElement.tap()` lands on the element's centre,
/// which for a full-width row is the dead space between the name and the value — exactly
/// where a reader's tap misses too.
///
/// So all three are `Menu`s now. `transitionRow` already had to be one for a reason of its
/// own — "a picker's rows cannot be individually disabled, and a disabled segment cannot carry
/// a reason" — and this is the second reason, which applies to every row in the section.
///
/// **This reads source text**, the same trade `GlassIsUntintedTests` and `ReaderMenuTests`
/// make and explain: composing these views needs a simulator and `swift test` runs on the
/// host. It cannot press a row; it can see the control that made the row unpressable.
@Suite("The menu's settings rows open from anywhere on the row")
struct ReaderMenuHitAreaTests {

    /// The comic reader's settings rows, from this test's own compiled path. See
    /// `ReaderChromeTests` for why this is `#filePath` and not a walk up from the working
    /// directory.
    private static let settings: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ReaderFeatureTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // StoryArcKit
        .appending(path: "Sources/ReaderFeature/ReaderMenuSettings.swift")

    /// The file's code with its `//` prose removed — this suite's own paragraphs name every
    /// spelling it searches for.
    private func code() throws -> String {
        let text = try #require(
            try? String(contentsOf: Self.settings, encoding: .utf8),
            "\(Self.settings.path) could not be read — have the settings rows moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    @Test("No settings row is a picker")
    func noSettingsRowIsAPicker() throws {
        let source = try code()
        #expect(
            !source.contains("Picker("),
            """
            A settings row is a `Picker` again. A menu-styled picker in a `List` puts its \
            button on the trailing value alone, so the name of the setting is not tappable — \
            measured on a booted iPhone 17 Pro, where a tap on the word `Fit` did nothing and \
            a tap on `Screen ⌄` opened all four options. The row above it is a `Menu` and \
            opens from anywhere, so two rows drawn identically behave differently.
            """
        )
        #expect(
            !source.contains(".pickerStyle(.menu)"),
            """
            `.pickerStyle(.menu)` is back on a settings row. It is what makes a picker *look* \
            like the menu row beside it while being tappable only at its trailing edge.
            """
        )
    }

    /// Each of the three choices is a menu, counted so that converting one and forgetting the
    /// others fails rather than passing on the first.
    @Test("All three choices are menus")
    func allThreeChoicesAreMenus() throws {
        let source = try code()
        let menus = source.ranges(of: "Menu {").count
        #expect(
            menus >= 3,
            """
            The settings section offers three choices — the page transition, the fit and the \
            reading direction — and \(menus) of them is a `Menu`. A row that is not one is a \
            row a reader cannot open by its name.
            """
        )
    }

    /// The affordance the pickers carried, kept.
    ///
    /// A menu-styled picker draws `chevron.up.chevron.down` after its value, which is the
    /// platform's own way of saying *this opens something*. `transitionRow` never had one, so
    /// converting the other two without adding it would have taken the affordance away from a
    /// section rather than given it to one.
    @Test("Every choice row says it opens something")
    func everyChoiceRowCarriesTheChevron() throws {
        let source = try code()
        let chevrons = source.ranges(of: "chevron.up.chevron.down").count
        #expect(
            chevrons >= 1,
            """
            No settings row draws the up/down chevron any more. It is the only thing on these \
            rows that says they can be opened: the name is plain text and the value is plain \
            text, and a `Menu` draws no indicator of its own.
            """
        )
    }
}
