import Foundation
import Testing

@testable import EpubReaderFeature

/// The text-size stepper says what it adjusts.
///
/// **Why it needed saying.** `reading-themes` asks the stepper to be one control a screen
/// reader can adjust, so the sheet joins its headline, its two buttons and its percentage
/// footnote with `.accessibilityElement(children: .combine)`. Combining takes the name from
/// the children, so the control announced the run of words those children draw and no noun
/// saying what was being adjusted. The name is now stated, from the same key the headline
/// draws, so a rewording moves both at once.
///
/// **Only this control.** The alignment `Picker` in the same sheet is segmented, and a
/// segmented picker vends each segment as its own element — a label on the container may do
/// nothing or may rename the segments, and which of the two cannot be settled without a screen
/// reader. It is deliberately untouched, and
/// `reader-theming-and-page-transitions` task 7.6 is where listening to VoiceOver is tracked.
struct SteppedControlIsNamedTests {

    private static var package: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var sheet: String {
        let file = Self.package.appending(path: "Sources/EpubReaderFeature/ThemeAxesSheet.swift")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            fatalError("ThemeAxesSheet.swift is not at \(file.path) — has it moved?")
        }
        return text
    }

    @Test("The combined stepper carries a name of its own")
    func theStepperIsNamed() {
        #expect(sheet.contains(".accessibilityElement(children: .combine)"), "the control is no longer combined")
        #expect(
            sheet.contains("accessibilityLabel(Text(\"theme.fontSize\", bundle: .module))"),
            "the combined control takes its name from its children again"
        )
    }

    @Test("The name it speaks is the name it draws, in all four languages")
    func theNameIsDrawnAndTranslated() throws {
        #expect(sheet.contains("Text(\"theme.fontSize\", bundle: .module)"), "the headline no longer draws that key")

        let file = Self.package.appending(path: "Sources/EpubReaderFeature/Resources/Localizable.xcstrings")
        let root = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]
        )
        let strings = try #require(root["strings"] as? [String: Any])
        let entry = try #require(strings["theme.fontSize"] as? [String: Any], "theme.fontSize is in no catalogue")
        let localizations = try #require(entry["localizations"] as? [String: Any])

        #expect(Set(localizations.keys) == ["de", "en", "es", "fr"], "spoken in \(localizations.keys.sorted())")
    }
}
