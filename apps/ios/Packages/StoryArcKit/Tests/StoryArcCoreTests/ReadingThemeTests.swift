import Foundation
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

    // MARK: - Contrast

    @Test("Black on white is the extreme WCAG defines, and a colour on itself is the floor")
    func contrastBounds() {
        #expect(abs(ReadingContrast.ratio("#000000", "#FFFFFF") - 21) < 0.01)
        #expect(abs(ReadingContrast.ratio("#FFFFFF", "#000000") - 21) < 0.01)
        #expect(abs(ReadingContrast.ratio("#3A5F8A", "#3A5F8A") - 1) < 0.0001)
    }

    @Test("A colour it cannot read is the worst ratio, never the best")
    func malformedHexIsNotAPass() {
        // The failure mode that matters: a typo must not be the reason a pairing is
        // accepted, so an unreadable colour reports 1 rather than nil or 21.
        #expect(ReadingContrast.ratio("not a colour", "#FFFFFF") == 1)
        #expect(ReadingContrast.luminance(of: "#12345") == nil)
        // Three-digit hex is legal CSS and a picker may hand one over.
        #expect(abs(ReadingContrast.ratio("#fff", "#000000") - 21) < 0.01)
    }

    @Test("The runtime maths agrees with the token pipeline's, to four places")
    func agreesWithTheTokenGate() {
        // Golden values from `packages/design-tokens/scripts/oklch.mjs`, which is what
        // fails the build when a reading theme drops below 7:1. If the two drifted, a
        // pairing could pass the gate and be refused in the sheet, or worse the other
        // way round. Paper's own pair, and the mid-grey ceiling.
        #expect(abs(ReadingContrast.ratio("#F5F1EC", "#1D1A17") - 15.4044) < 0.0001)
        #expect(abs(ReadingContrast.ratio("#808080", "#000000") - 5.3172) < 0.0001)
    }

    @Test("A derived text colour is the better of black and white")
    func derivationTakesTheExtreme() {
        #expect(ReaderPalette.derived(name: "n", background: "#FFFFFF").foreground == "#000000")
        #expect(ReaderPalette.derived(name: "n", background: "#101010").foreground == "#FFFFFF")
    }

    @Test("A mid-tone background is reported as unable to reach AAA rather than dressed up")
    func midToneCannotReachAAA() {
        // Grey tops out near 5.3 against black. The honest answer is that no text
        // colour reaches 7:1 on it — silently returning black would look like a pass.
        let grey = ReaderPalette.derived(name: "grey", background: "#808080")
        #expect(grey.isReadable)
        #expect(!grey.meetsAAA)
    }

    @Test("A pairing below AA is refused, and the ratio survives to be shown")
    func illegibleOverrideIsRefusedWithItsNumber() {
        // `reading-themes` refuses below 4.5:1 "with the measured ratio stated", so
        // the attempt has to exist as a value long enough to be measured.
        let tried = ReaderPalette
            .derived(name: "n", background: "#FFFFFF")
            .overriding(foreground: "#DDDDDD")
        #expect(!tried.isReadable)
        #expect(tried.contrast > 1)
    }

    // MARK: - The seventh slot

    @Test("Custom colours sit alongside the presets and keep the typography")
    func customIsASeventhSlot() {
        let palette = ReaderPalette.derived(name: "Sea", background: "#0B2027")
        let theme = ReadingTheme(preset: .calm, deviations: [.lineSpacing]).adopting(palette)
        #expect(theme.isCustom)
        // The preset is not overwritten, and the reader's line height survives.
        #expect(theme.preset == .calm)
        #expect(theme.deviations == [.lineSpacing])
        #expect(theme.discardingCustomColours().custom == nil)
    }

    @Test("Tapping one of the six leaves the reader's own palette behind")
    func adoptingAPresetDropsTheCustomColours() {
        let theme = ReadingTheme().adopting(ReaderPalette.derived(name: "Sea", background: "#0B2027"))
        #expect(theme.adopting(ThemePreset.focus).custom == nil)
        #expect(theme.restored().custom == nil)
    }

    @Test("Original refuses custom colours, because the publisher's are the point")
    func originalKeepsItsOwnColours() {
        let theme = ReadingTheme(preset: .original)
            .adopting(ReaderPalette.derived(name: "Sea", background: "#0B2027"))
        #expect(!theme.isCustom)
    }

    // MARK: - Remembering

    @Test("A theme set on one book in a series is what the next book in it opens with")
    func perSeriesMemory() {
        let chosen = StoredTheme(theme: ReadingTheme(preset: .calm))
        let memory = ThemeMemory()
            .remembering(chosen, for: .reflowable, shelf: "Bone")
        #expect(memory.theme(for: .reflowable, shelf: "Bone").theme.preset == .calm)
        // A shelf never opened falls through to the default, not to the last book read.
        #expect(memory.theme(for: .reflowable, shelf: "Blame!").theme.preset == .paper)
    }

    @Test("Reflowable and fixed-layout keep separate defaults for the same shelf name")
    func scopesDoNotCollide() {
        // A series called "Bone" can hold both a comic and an ebook, and a line height
        // means nothing to a page of artwork.
        let memory = ThemeMemory()
            .remembering(StoredTheme(theme: ReadingTheme(preset: .calm)), for: .reflowable, shelf: "Bone")
            .remembering(StoredTheme(theme: ReadingTheme(preset: .quiet)), for: .fixedLayout, shelf: "Bone")
        #expect(memory.theme(for: .reflowable, shelf: "Bone").theme.preset == .calm)
        #expect(memory.theme(for: .fixedLayout, shelf: "Bone").theme.preset == .quiet)
    }

    @Test("Changing the global default leaves a choice already made alone")
    func defaultDoesNotOverwriteAShelf() {
        let memory = ThemeMemory()
            .remembering(StoredTheme(theme: ReadingTheme(preset: .calm)), for: .reflowable, shelf: "Bone")
            .settingDefault(StoredTheme(theme: ReadingTheme(preset: .focus)), for: .reflowable)
        #expect(memory.theme(for: .reflowable, shelf: "Bone").theme.preset == .calm)
        #expect(memory.theme(for: .reflowable, shelf: "unopened").theme.preset == .focus)
        // And it does not leak across scopes.
        #expect(memory.theme(for: .fixedLayout, shelf: "unopened").theme.preset == .paper)
    }

    @Test("A book with no series is a series of one, not the global default")
    func standaloneBookIsItsOwnShelf() {
        // Otherwise reading one novel in sepia would change every other book.
        #expect(ThemeMemory.shelf(series: "Bone", identity: "abc") == "Bone")
        #expect(ThemeMemory.shelf(series: nil, identity: "abc") == "abc")
        #expect(ThemeMemory.shelf(series: "   ", identity: "abc") == "abc")
    }

    @Test("A deviation survives a round trip, because the values travel with the theme")
    func deviationsSurvive() throws {
        var values = ThemePreset.paper.values
        values.lineHeight = 2.1
        let stored = StoredTheme(
            theme: ReadingTheme(preset: .paper, deviations: [.lineSpacing]),
            values: values
        )
        let memory = ThemeMemory().remembering(stored, for: .reflowable, shelf: "Bone")
        let encoded = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(ThemeMemory.self, from: encoded)
        let read = decoded.theme(for: .reflowable, shelf: "Bone")
        #expect(read.values.lineHeight == 2.1)
        #expect(read.theme.isModified)
    }

    @Test("A custom palette survives a round trip too")
    func customColoursSurvive() throws {
        let palette = ReaderPalette.derived(name: "Sea", background: "#0B2027")
        let stored = StoredTheme(theme: ReadingTheme().adopting(palette))
        let memory = ThemeMemory().remembering(stored, for: .reflowable, shelf: "Bone")
        let encoded = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(ThemeMemory.self, from: encoded)
        #expect(decoded.theme(for: .reflowable, shelf: "Bone").theme.custom == palette)
    }

    // MARK: - Axis units

    @Test("An axis that has a slider can say what its number means, and one that has no slider says nothing")
    func everySliderCanSpeak() {
        // The invariant that matters: a tenth axis added to `sliderRange` and
        // forgotten here would ship a slider a screen reader reads as a bare float.
        for axis in ThemeAxis.allCases {
            #expect((axis.unit != nil) == (axis.sliderRange != nil), "\(axis)")
            #expect((axis.step != nil) == (axis.sliderRange != nil), "\(axis)")
        }
    }

    @Test("A whole ladder of adjustments crosses an axis from end to end")
    func stepCrossesTheRange() {
        for axis in ThemeAxis.allCases {
            guard let range = axis.sliderRange, let step = axis.step else { continue }
            let crossed = range.lowerBound + step * Double(ThemeAxis.stepsPerAxis)
            #expect(abs(crossed - range.upperBound) < 0.0001, "\(axis)")
        }
    }
}
