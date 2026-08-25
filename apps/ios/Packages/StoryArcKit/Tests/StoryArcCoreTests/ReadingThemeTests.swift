import Testing

@testable import StoryArcCore

/// The theme model: which preset is on, which axes reach the page, and when a
/// preset counts as modified.
///
/// `reading-themes` is specific about all three, and all three are the kind of rule
/// that is easy to get subtly wrong in a sheet full of sliders. Android's
/// `ReadingThemeTest` asserts the same table.
@Suite("Reading themes")
struct ReadingThemeTests {

    // MARK: - Presets

    @Test("Six presets, and only Original keeps the publisher's stylesheet")
    func presets() {
        #expect(ThemePreset.allCases.count == 6)
        #expect(ThemePreset.original.keepsPublisherStyles)
        for preset in ThemePreset.allCases where preset != .original {
            #expect(!preset.keepsPublisherStyles, "\(preset) should override the publisher")
        }
    }

    @Test("Nine axes, and the spacing ones need the publisher's styles off")
    func axes() {
        #expect(ThemeAxis.allCases.count == 9)
        // From `design.md`'s mapping table — Readium's behaviour, not ours.
        for axis in [ThemeAxis.fontSize, .fontFamily, .boldText, .margins] {
            #expect(!axis.requiresPublisherStylesOff, "\(axis) reaches the page regardless")
        }
        for axis in [
            ThemeAxis.lineSpacing, .characterSpacing, .wordSpacing, .paragraphSpacing, .textAlignment,
        ] {
            #expect(axis.requiresPublisherStylesOff, "\(axis) is overridden by publisher CSS")
        }
    }

    // MARK: - What reaches the page

    @Test("Under Original the spacing axes cannot reach the page")
    func originalDisablesSpacing() {
        let theme = ReadingTheme(preset: .original)

        #expect(theme.isEffective(.fontSize))
        #expect(theme.isEffective(.margins))
        #expect(!theme.isEffective(.lineSpacing))
        #expect(!theme.isEffective(.textAlignment))
        // Four of nine, which is what the sheet has to show as unavailable.
        #expect(theme.effectiveAxes.count == 4)
    }

    @Test("Under every other preset all nine axes reach the page")
    func othersEnableEverything() {
        for preset in ThemePreset.allCases where preset != .original {
            #expect(ReadingTheme(preset: preset).effectiveAxes.count == 9)
        }
    }

    // MARK: - Deviation

    @Test("A fresh preset is active rather than modified")
    func freshPreset() {
        #expect(!ReadingTheme(preset: .paper).isModified)
    }

    @Test("Moving an axis marks the preset modified and keeps it selected")
    func deviating() {
        let theme = ReadingTheme(preset: .paper).deviating(on: .lineSpacing)

        #expect(theme.isModified)
        // `reading-themes`: "the preset stays selected and is marked as modified".
        #expect(theme.preset == .paper)
        #expect(theme.deviations == [.lineSpacing])
    }

    @Test("An axis that cannot reach the page is not a deviation")
    func inertAxisIsNotADeviation() {
        // Nothing changed on the page, so calling Original modified would be a lie
        // the reader can see.
        let theme = ReadingTheme(preset: .original).deviating(on: .lineSpacing)

        #expect(!theme.isModified)
        #expect(theme.deviations.isEmpty)
    }

    @Test("Restoring puts the preset back without changing which one it is")
    func restoring() {
        let theme = ReadingTheme(preset: .calm)
            .deviating(on: .fontSize)
            .deviating(on: .margins)
            .restored()

        #expect(theme.preset == .calm)
        #expect(!theme.isModified)
    }

    @Test("Adopting a preset does not carry the last one's deviations across")
    func adoptingClearsDeviations() {
        // Otherwise the preset the reader just tapped is not the one they get.
        let theme = ReadingTheme(preset: .paper)
            .deviating(on: .fontSize)
            .adopting(.focus)

        #expect(theme.preset == .focus)
        #expect(!theme.isModified)
    }

    // MARK: - Font size steps

    @Test("The ladder spans at least seven steps and includes the publication's own size")
    func fontSizeLadder() {
        // `reading-themes` asks for at least seven steps, which is the only
        // constraint on the count. What matters beyond that is that the
        // publication's own size is reachable — a ladder a reader cannot get back
        // to 100% on is a ladder they are stuck on.
        #expect(FontSizeStep.count >= 7)
        #expect(FontSizeStep.allCases.contains(.normal))
        #expect(FontSizeStep.normal.fraction == 1)
        #expect(FontSizeStep.normal.position > 0)
        #expect(FontSizeStep.normal.position < FontSizeStep.count - 1)
    }

    @Test("Stepping stops at each end rather than wrapping")
    func fontSizeClamps() {
        #expect(FontSizeStep.smallest.previous == .smallest)
        #expect(FontSizeStep.hugest.next == .hugest)
        #expect(FontSizeStep.normal.next.previous == .normal)
    }

    @Test("The ladder rises monotonically, so a step is always a change")
    func fontSizeMonotonic() {
        let sizes = FontSizeStep.allCases.map(\.rawValue)
        #expect(sizes == sizes.sorted())
        #expect(Set(sizes).count == sizes.count)
    }

    // MARK: - Preset values

    @Test("Original overrides nothing but size")
    func originalOverridesNothing() {
        let values = ThemePreset.original.values
        #expect(values.typeface == .publisher)
        #expect(values.textAlignment == .publisher)
        #expect(values == ThemeValues(), "Original is the defaults, by definition")
    }

    @Test("Every other preset states a typeface")
    func presetsPickATypeface() {
        for preset in ThemePreset.allCases where preset != .original {
            #expect(preset.values.typeface != .publisher, "\(preset) should choose a face")
        }
    }

    @Test("Bold opens larger and heavier, because that is what it is for")
    func boldIsBolder() {
        let bold = ThemePreset.bold.values
        #expect(bold.isBold)
        #expect(bold.fontSize > .normal)
        #expect(bold.lineHeight > ThemePreset.paper.values.lineHeight)
    }

    @Test("Focus has the widest margins, which is what a narrow measure means")
    func focusIsNarrow() {
        let widest = ThemePreset.allCases.map(\.values.pageMargins).max()
        #expect(ThemePreset.focus.values.pageMargins == widest)
    }

    @Test("Calm has the most generous line height")
    func calmIsAiry() {
        let tallest = ThemePreset.allCases.map(\.values.lineHeight).max()
        #expect(ThemePreset.calm.values.lineHeight == tallest)
    }

    // MARK: - Transitions

    @Test("Reduce Motion substitutes the fast fade, and leaves the scroll modes alone")
    func reduceMotion() {
        #expect(PageTransition.pageCurl.honoring(reduceMotion: true) == .fastFade)
        #expect(PageTransition.slide.honoring(reduceMotion: true) == .fastFade)
        // Scrolling is not an animation the reader did not ask for.
        #expect(PageTransition.verticalScroll.honoring(reduceMotion: true) == .verticalScroll)
        #expect(PageTransition.pageCurl.honoring(reduceMotion: false) == .pageCurl)
    }
}
