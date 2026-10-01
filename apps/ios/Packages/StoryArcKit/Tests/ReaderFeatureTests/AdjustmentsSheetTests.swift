import Foundation
import Testing

/// That the image-adjustment sheet offers every adjustment the reader is promised.
///
/// `comic-reader`, *Adjustments available*:
///
/// > **THEN** brightness, contrast, sharpness, colour inversion, and greyscale are available
/// > with a live preview
///
/// `comic-reader`, *Cropping borders*:
///
/// > **WHEN** a user enables border cropping
/// > **THEN** uniform white or black margins are detected and trimmed per page, and the user
/// > can disable it for a page that crops wrongly
///
/// **This suite exists because border cropping was dead on iOS.** `BorderCrop` detects the
/// margin, `cropped(_:when:)` applies it, `ReaderView` holds the excused pages, and the
/// catalogue carries `reader.adjust.crop` in four languages — but the sheet drew no switch
/// for any of it, so `cropsBorders` was false on every page of every publication and no
/// reader could turn it on. Eight tests asserted the detection. Nothing asserted that a
/// reader could reach it.
///
/// **Why it reads the source text, which is the second-best test.** The honest test taps the
/// sheet on a booted simulator and reads the switches. `pnpm test:ios` runs `swift test` on
/// the host, where there is no screen to tap, and no gate in this repository boots a
/// simulator. `ReaderChromeTests` and `ReaderMenuTests` are the same choice made for the
/// same reason and carry the same warning: this is a tripwire, not a proof. It says the
/// sheet binds a control to each value; it never says a switch appeared.
///
/// The keys themselves are not checked here. `scripts/ios-strings.mjs` reads every literal
/// key in the sources and fails the build on one the catalogue cannot answer in all four
/// languages, and these are literal keys.
@Suite("The adjustments sheet offers every adjustment")
struct AdjustmentsSheetTests {

    /// The package directory, from this test's own compiled path.
    ///
    /// `#filePath` and not a walk up from the working directory: this repository nests agent
    /// worktrees at `.claude/worktrees/<name>/`, and a walk that climbs looking for a marker
    /// leaves the checkout under test and guards the parent's copy.
    private static let package: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static var sheet: URL {
        package.appending(path: "Sources/ReaderFeature/AdjustmentsSheet.swift")
    }

    /// One adjustment, and the binding that makes a control change it.
    ///
    /// The binding rather than the label: a label can be drawn beside a control that writes
    /// nothing, and that is the shape the defect had — the sheet declared `cropsThisPage` and
    /// bound no control to it.
    private struct Control {
        let what: String
        let binding: String
    }

    private static let controls: [Control] = [
        Control(what: "brightness", binding: "$adjustments.brightness"),
        Control(what: "contrast", binding: "$adjustments.contrast"),
        Control(what: "sharpness", binding: "$adjustments.sharpness"),
        Control(what: "colour inversion", binding: "$adjustments.isInverted"),
        Control(what: "greyscale", binding: "$adjustments.isGreyscale"),
        Control(what: "border cropping", binding: "$adjustments.cropsBorders"),
        Control(what: "excusing this page from the crop", binding: "$cropsThisPage"),
        // D34: `ebook-reader`'s *Fixed-layout EPUB* asks for these two from the container,
        // not from a filter over the artwork — see `ReaderMatte.swift`'s doc comment.
        Control(what: "the matte", binding: "model.chooseMatte(hex)"),
        Control(what: "reader-local screen brightness", binding: "set: { model.brightness = $0 }"),
    ]

    /// The sheet's code, with its prose removed.
    ///
    /// Comments are stripped first: this codebase explains itself at length, and every
    /// spelling below appears in a comment somewhere. A guard that found a binding named in a
    /// paragraph about that binding would be measuring the documentation.
    private func code() throws -> String {
        let text = try #require(
            try? String(contentsOf: Self.sheet, encoding: .utf8),
            "\(Self.sheet.path) could not be read — has the adjustments sheet moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    @Test("Every adjustment the scenario names has a control bound to it")
    func everyAdjustmentIsReachable() throws {
        let code = try code()
        for control in Self.controls {
            #expect(
                code.contains(control.binding),
                """
                The adjustments sheet binds no control to \(control.what) — \
                `\(control.binding)` is nowhere in its source. `comic-reader` requires \
                brightness, contrast, sharpness, colour inversion and greyscale to be \
                available, and border cropping to be something "a user enables" and can \
                "disable ... for a page that crops wrongly". A value nothing writes to is a \
                feature no reader can reach, which is what this file shipped without.
                """
            )
        }
    }

    /// The per-page switch is offered only where there is a trim to excuse the page from.
    ///
    /// Not a second decision the reader is asked to make about a series that is not being
    /// trimmed: `comic-reader` scopes the exception to "a page that crops wrongly", and no
    /// page crops wrongly while nothing crops at all.
    @Test("The per-page exception is offered only while the series is being trimmed")
    func theExceptionIsConditional() throws {
        let code = try code()
        #expect(
            code.contains("if adjustments.cropsBorders {"),
            """
            The adjustments sheet offers the per-page exception unconditionally. \
            `comic-reader` scopes it to "a page that crops wrongly", and a switch that \
            excuses a page from a trim nobody asked for states a choice the reader does not \
            have.
            """
        )
    }
}
