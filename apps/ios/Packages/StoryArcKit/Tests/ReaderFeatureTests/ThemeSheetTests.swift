import Foundation
import Testing

/// That the theme surface has two levels, that level one is only presets, and that the reset
/// on level two names what it restores.
///
/// `ebook-reader`, *The theme surface opens on the presets*:
///
/// > **THEN** the six preset swatches are what is shown, with no axis control among them
/// > **AND** one action, given equal prominence to the grid, opens the axes
/// > **AND** picking a preset applies it and leaves the surface, because that was the whole
/// > errand
///
/// `reading-themes`, *The reset names what it restores* and *Resetting the preset that is
/// already unmodified*.
///
/// ``ThemeResetTests`` in `StoryArcCoreTests` owns what a reset *does*, over the pure type,
/// and it found a real defect doing it. This owns where the two levels are *drawn* and which
/// controls are on which — and no host test can measure that, so it reads the source and is a
/// tripwire rather than a proof. It says level one declares no slider; it never says a slider
/// failed to appear.
///
/// **Why the absence is the assertion.** The whole change is that nine sliders stopped being
/// the first thing a reader met. Nothing in a compiler notices one coming back, and the file
/// they would come back to is the one that used to hold them.
@Suite("The theme surface has two levels")
struct ThemeSheetTests {

    /// The reflowable reader's sources, from this test's own compiled path. See
    /// `ReaderChromeTests` for why this is `#filePath`.
    private static let reader: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "StoryArcEpub/Sources/EpubReaderFeature")

    private func code(of name: String) throws -> String {
        let url = Self.reader.appending(path: name)
        let text = try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has \(name) moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    @Test("Level one shows the presets and no axis control")
    func levelOneIsOnlyPresets() throws {
        let code = try code(of: "ThemeSheet.swift")

        #expect(code.contains("presets"), "level one still draws the preset grid")

        // The *definitions*, not the uses: a body that referenced one without defining it
        // would not compile, and `alignment:` and `typeface:` are argument labels level one
        // legitimately passes to a `VStack` and to the custom card.
        let axes: [(what: String, spelling: String)] = [
            ("a slider", "Slider("),
            ("the font-size stepper", "private var fontSize"),
            ("the typeface picker", "private var typeface"),
            ("the spacing sliders", "private var fineAxes"),
            ("the alignment picker", "private var alignment"),
            ("the brightness slider", "private var brightness"),
            ("the page colours", "PageColourSection("),
            ("the page-turn picker", "pageTurn"),
        ]
        for axis in axes {
            #expect(
                !code.contains(axis.spelling),
                """
                Level one draws \(axis.what) — `\(axis.spelling)` is in `ThemeSheet.swift`. \
                `ebook-reader`: "the six preset swatches are what is shown, with no axis \
                control among them". A reader who wants Paper must not scroll past nine \
                sliders to find it.
                """
            )
        }
    }

    @Test("One action of equal prominence opens the axes, as a second sheet")
    func oneActionOpensTheAxes() throws {
        let code = try code(of: "ThemeSheet.swift")

        #expect(
            code.contains("private var customise: some View"),
            "level one has no action that opens the axes"
        )
        #expect(
            code.contains(".buttonStyle(.borderedProminent)"),
            """
            The action that opens the axes is not prominent. `ebook-reader` gives it "equal \
            prominence to the grid" — a footnote under six cards is not that.
            """
        )
        #expect(
            code.contains("ThemeAxesSheet(model: model, excerpt: excerpt)"),
            """
            Level one does not present `ThemeAxesSheet`. On iOS level two is "a second \
            `.sheet` presented from the first", which the platform animates as a stack. \
            Android's is a destination instead, and `design.md` records why.
            """
        )
    }

    @Test("Picking a preset applies it and leaves the surface")
    func pickingAPresetLeaves() throws {
        let code = try code(of: "ThemeSheet.swift")

        #expect(
            code.contains("model.adopt(preset)"),
            "picking a preset no longer applies it"
        )
        #expect(
            code.contains("dismiss()"),
            """
            Level one does not dismiss when a preset is picked. `ebook-reader`: "picking a \
            preset applies it and leaves the surface, because that was the whole errand".
            """
        )
    }

    @Test("Level two draws the specimen, every axis, and the reset")
    func levelTwoHoldsTheAxes() throws {
        let code = try code(of: "ThemeAxesSheet.swift")

        let expected: [(what: String, spelling: String)] = [
            ("the live specimen of the publication's own text", "ThemePreview("),
            ("the font-size stepper", "fontSize"),
            ("the typeface picker", "typeface"),
            ("the spacing sliders", "fineAxes"),
            ("the alignment picker", "alignment"),
            ("the brightness slider", "brightness"),
            ("the reset", "model.restoreTheme()"),
            ("the notice for axes Original cannot honour", "publisherNotice"),
        ]
        for item in expected {
            #expect(
                code.contains(item.spelling),
                """
                Level two is missing \(item.what) — `\(item.spelling)` is not in \
                `ThemeAxesSheet.swift`. `ebook-reader` requires "the axes offered are exactly \
                those in `reading-themes`, with none added and none dropped", over "a \
                specimen of the publication's own text in the active theme, which updates as \
                an axis changes".
                """
            )
        }
    }

    @Test("Every axis states its value beside its control, once")
    func everyAxisStatesItsValue() throws {
        // The sliders live beside the sheet: level two reached this project's 400-line
        // ceiling once it became a file of its own, and the continuous axes are the seam.
        let code = try code(of: "ThemeAxesSheet.swift") + code(of: "ThemeAxisSliders.swift")

        #expect(
            code.contains("func axisHeader("),
            """
            Level two has no axis header. `reading-themes`: "its current value is stated \
            beside it in the reader's own language and units, and updates as the control \
            moves".
            """
        )
        #expect(
            code.contains(".accessibilityHidden(true)"),
            """
            The visible value is not hidden from assistive technology. `reading-themes` \
            requires the value to be available "as part of the control rather than as a \
            separate unlabelled element" — a label left visible to VoiceOver lands between \
            the axis's name and its slider and reads a bare number, which is exactly the \
            separate element the requirement names.
            """
        )
        // Every slider carries the axis's own name and its own value.
        let sliders = code.ranges(of: "Slider(").count
        let values = code.ranges(of: ".accessibilityValue(").count
        #expect(
            values >= sliders,
            """
            \(sliders) slider(s) on level two and only \(values) accessibility value(s). \
            `reading-themes` requires the value to be part of the control, so every slider \
            owes one.
            """
        )
    }

    @Test("The reset names its preset, is absent when unmodified, and is low-emphasis")
    func theResetNamesItsPreset() throws {
        let code = try code(of: "ThemeAxesSheet.swift")

        #expect(
            code.contains("if model.theme.isModified {"),
            """
            The reset is not gated on the preset being modified. `reading-themes`: the action \
            is "absent rather than present and doing nothing, because a control that never \
            changes anything teaches a reader to distrust the ones that do".
            """
        )
        #expect(
            code.contains("theme.restore.named"),
            """
            The reset does not name the preset it restores. `reading-themes`: "the reader who \
            modified Calm is offered Calm back, not an unnamed default".
            """
        )
        #expect(
            code.contains(".buttonStyle(.borderless)"),
            """
            The reset is not low-emphasis. `design.md`: a plain borderless button, because \
            **Material has nothing to say about reset-to-defaults** — no component, no \
            pattern — and the Dialogs page's discard-unsaved-changes prompt is about \
            abandoning edits rather than restoring defaults.
            """
        )
        #expect(
            !code.contains("confirmationDialog"),
            """
            The reset asks for confirmation. It should not: it is immediately reversible by \
            picking the preset again, and a dialogue over an undoable change is one a reader \
            learns to dismiss unread.
            """
        )
    }

    @Test("The reset takes the same path a type-size change does, and leaves the sheet up")
    func theResetKeepsTheReadingPosition() throws {
        let model = try code(of: "EpubReaderModel.swift")

        // `reading-themes`: "the reading position is preserved to the paragraph across the
        // repagination, exactly as a type-size change is". It *is* a type-size change as far
        // as the renderer is concerned — both go through `applyTheme()`, which reads the
        // locator before submitting preferences and goes back to it afterwards, because
        // Readium lands on the progression rather than the paragraph. Asserting the shared
        // path is what stops a reset that submits preferences directly and skips the return.
        #expect(
            model.contains("public func restoreTheme() {"),
            "`restoreTheme` has moved; this guard names it"
        )
        let restore = try #require(model.range(of: "public func restoreTheme() {"))
        let body = model[restore.upperBound...].prefix(while: { $0 != "}" })
        #expect(
            body.contains("applyTheme()"),
            """
            `restoreTheme` no longer goes through `applyTheme()`. That function is where \
            the reading position survives the repagination — it reads the locator, submits \
            the preferences, and goes back to it, because Readium lands on the progression \
            rather than the paragraph. `reading-themes` requires the reset to preserve the \
            position "exactly as a type-size change is", and a type-size change is the \
            other caller.
            """
        )

        let sheet = try code(of: "ThemeAxesSheet.swift")
        let reset = try #require(sheet.range(of: "private var reset: some View {"))
        let resetBody = sheet[reset.upperBound...].prefix(400)
        #expect(
            !resetBody.contains("dismiss()"),
            """
            The reset dismisses level two. `reading-themes` asks for the change to be \
            "visible behind the sheet without the sheet being dismissed" — and the specimen \
            at the top of level two is the nearer proof, because it repaints as the values \
            go back.
            """
        )
    }

    @Test("Both levels survive the largest accessibility text size")
    func bothLevelsScaleUp() throws {
        let one = try code(of: "ThemeSheet.swift")
        let two = try code(of: "ThemeAxesSheet.swift")
        let sliders = try code(of: "ThemeAxisSliders.swift")

        // `ebook-reader`, *Both levels at the largest text size*: "every preset name, axis
        // label and value is readable in full, the surface scrolls if it must, and the action
        // that opens the axes stays reachable **AND** no label is truncated to fit its value."
        //
        // Three things a source guard can actually check, and a screenshot is what proves the
        // fourth. The two that matter most are the scroll — without it the action under the
        // grid is simply off the bottom of the sheet at twice the text size — and the absence
        // of a line limit on the axis rows, which is the mechanism by which a label gets
        // truncated to fit its value.
        for level in [(name: "Level one", code: one), (name: "Level two", code: two)] {
            #expect(
                level.code.contains("ScrollView {"),
                """
                \(level.name) does not scroll. At the largest accessibility text size the        \
                preset grid alone is taller than a phone, so the action that opens the axes      \
                would be off the bottom of a surface that cannot move.
                """
            )
        }

        #expect(
            !sliders.contains("lineLimit(1)"),
            """
            An axis row limits its label to one line. `ebook-reader`: "no label is \
            truncated to fit its value beside it" — the name and the value share a row, so \
            a line limit on the name is exactly how the truncation happens.
            """
        )
        #expect(
            sliders.contains("Spacer(minLength: StoryArcSpace.sm)"),
            """
            The axis row has no minimum gap between its name and its value. Without one \
            the two run together at a large text size, which is the same defect as a \
            truncation wearing a different name.
            """
        )
    }
}
