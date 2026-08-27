public import SwiftUI

internal import DesignSystem
internal import UIKit

public import StoryArcCore

/// The reading-theme sheet.
///
/// `ebook-reader` and `reading-themes` between them ask for a preset grid, a
/// stepped font size with a visible position, and — the part that is easy to skip —
/// an axis that cannot reach the page shown "unavailable with a one-line reason and
/// a single action that turns publisher styles off". Not hidden, and not a live
/// control that does nothing.
///
/// Custom backgrounds are Phase 3.7 and are not here yet. Everything else the
/// spec describes at both levels is.
struct ThemeSheet: View {
    @Environment(\.theme) var theme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dismiss) private var dismiss

    let model: EpubReaderModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                    presets
                    pageTurn
                    fontSize
                    typeface
                    if model.theme.preset.keepsPublisherStyles {
                        publisherNotice
                    } else {
                        fineAxes
                        alignment
                        // A custom background cannot apply under Original, where
                        // the publisher's own colours are the point — so it lives
                        // in the same branch as the other overrides.
                        PageColourSection(
                            palette: model.theme.custom,
                            onAdopt: { model.adoptColours($0) },
                            onDiscard: model.discardCustomColours
                        )
                    }
                    brightness
                }
                .padding(StoryArcSpace.gutter)
            }
            // No background of our own. A sheet on iOS 26 is already presented
            // on Liquid Glass, and `native-experience` wants it "left untinted so
            // it picks up the page beneath it" — an opaque fill here is the one
            // thing that would prevent that. The system's material also carries
            // its own Reduce-Transparency fallback, so declaring a second one
            // would only be able to disagree with it.
            // Inline, not a large title. A large title puts the sheet's name on its own
            // line under the toolbar, which costs a reader about 60 points of the page
            // they came here to adjust — on a sheet that is already only half the screen.
            .navigationTitle(Text("theme.title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("theme.done", bundle: .module) }
                }
                if model.theme.isModified {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { model.restoreTheme() } label: {
                            Text("theme.restore", bundle: .module)
                        }
                    }
                }
            }
        }
    }

    /// Three by two, each card in its own colours.
    ///
    /// `ebook-reader`: the grid previews "each preset in its own colours — six
    /// samples, not six labels". A swatch that took the app's palette would be six
    /// identical cards with different words on them.
    private var presets: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.presets", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                // The trait, not `textRole`, is what lets VoiceOver jump section to section.
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(
                columns: Array(repeating: GridItem(spacing: StoryArcSpace.sm), count: 3),
                spacing: StoryArcSpace.sm
            ) {
                ForEach(ThemePreset.allCases, id: \.self) { preset in
                    PresetCard(
                        preset: preset,
                        isActive: model.theme.preset == preset && !model.theme.isCustom,
                        isModified: model.theme.preset == preset && model.theme.isModified
                    ) {
                        model.adopt(preset)
                    }
                }
                // The seventh slot, present only once the reader has made one.
                // `reading-themes` puts it "alongside the six presets rather than
                // overwriting one", so it is a seventh card and not a replaced one.
                if let custom = model.theme.custom {
                    CustomCard(palette: custom, typeface: model.values.typeface) {
                        model.adoptColours(custom)
                    }
                }
            }
        }
    }

    /// `reading-themes`: stepped, with the position shown, never a free slider.
    private var fontSize: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.fontSize", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)

            HStack(spacing: StoryArcSpace.md) {
                Button { step(to: model.values.fontSize.previous) } label: {
                    Label {
                        Text("theme.fontSize.smaller", bundle: .module)
                    } icon: {
                        Image(systemName: "textformat.size.smaller")
                    }
                    .labelStyle(.iconOnly)
                }
                .disabled(model.values.fontSize == FontSizeStep.allCases.first)

                StepDots(position: model.values.fontSize.position, count: FontSizeStep.count)

                Button { step(to: model.values.fontSize.next) } label: {
                    Label {
                        Text("theme.fontSize.larger", bundle: .module)
                    } icon: {
                        Image(systemName: "textformat.size.larger")
                    }
                    .labelStyle(.iconOnly)
                }
                .disabled(model.values.fontSize == FontSizeStep.allCases.last)
            }
            .buttonStyle(.bordered)

            Text("theme.fontSize.percent \(model.values.fontSize.rawValue)", bundle: .module)
                .textRole(.footnote)
                .monospacedDigit()
                .foregroundStyle(theme.palette.textTertiary)
        }
        // One control, spoken as one: `reading-themes` asks for increment actions so
        // VoiceOver can adjust it rather than hunting two buttons.
        .accessibilityElement(children: .combine)
        // Position first, then the percentage. `native-experience` asks the stepper
        // to announce "its position out of the total rather than only larger" — a
        // percentage alone never says how much room is left on the ladder.
        .accessibilityValue(
            Text(
                "theme.fontSize.position \(model.values.fontSize.position + 1) \(FontSizeStep.count)",
                bundle: .module
            )
            + Text(verbatim: ", ")
            + Text("theme.fontSize.percent \(model.values.fontSize.rawValue)", bundle: .module)
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(to: model.values.fontSize.next)
            case .decrement: step(to: model.values.fontSize.previous)
            @unknown default: break
            }
        }
    }

    /// Typeface and weight: the two axes that reach the page even under Original.
    private var typeface: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.axis.fontFamily", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            // A list of rows rather than a menu, and each name drawn in the face it
            // names. A menu would fit more compactly, but SwiftUI strips a custom
            // font inside one — and a typeface picker whose options all look alike is
            // a list of words rather than a choice. Eight faces do not fit across a
            // phone either way, and `reading-themes` calls this axis a picker.
            ForEach(ReaderTypeface.allCases, id: \.self) { face in
                Button { typefaceBinding.wrappedValue = face } label: {
                    HStack(spacing: StoryArcSpace.sm) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(face.titleKey, bundle: .module)
                                .font(BundledFonts.font(face, size: 17))
                                .foregroundStyle(theme.palette.textPrimary)

                            if face.isDesignedForLowVision {
                                // `reading-themes`: labelled as such, because "an
                                // accessibility affordance presented as a style
                                // option gets missed by the people who need it".
                                Text("theme.typeface.lowVision", bundle: .module)
                                    .textRole(.caption)
                                    .foregroundStyle(theme.palette.textTertiary)
                            }
                        }

                        Spacer()

                        if model.values.typeface == face {
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.accent)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    model.values.typeface == face ? [.isButton, .isSelected] : .isButton
                )
            }

            Toggle(isOn: boldBinding) {
                Text("theme.axis.boldText", bundle: .module)
                    .textRole(.body)
                    .foregroundStyle(theme.palette.textPrimary)
            }
        }
    }

    /// A slider's value as a screen reader should say it.
    ///
    /// The unit comes from the domain, so the two platforms cannot describe the same
    /// slider differently. The number is formatted for the reader's locale, which is
    /// why this is not a plain interpolation — a comma decimal separator is not a
    /// detail a French reader should have to work around.
    private static func spoken(_ value: Double, in unit: AxisUnit?) -> Text {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        switch unit {
        case .multiple: return Text("theme.axis.value.multiple \(number)", bundle: .module)
        case .em: return Text("theme.axis.value.em \(number)", bundle: .module)
        case nil: return Text(verbatim: number)
        }
    }

    /// The sliders. One loop rather than five blocks, because the domain answers
    /// every question a slider asks: its range, its value, and how to set it.
    private var fineAxes: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            Text("theme.spacing", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(ThemeAxis.allCases, id: \.self) { axis in
                if let range = axis.sliderRange {
                    VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                        Text(axis.titleKey, bundle: .module)
                            .textRole(.footnote)
                            .foregroundStyle(theme.palette.textSecondary)

                        Slider(
                            value: Binding(
                                get: { model.values.value(of: axis) },
                                set: { model.set(axis, to: $0) }
                            ),
                            in: range,
                            // Stepped, so a screen reader's adjust action moves the
                            // value by something a reader can notice, and so a drag
                            // submits twenty preference changes to the renderer
                            // rather than one per frame.
                            step: axis.step ?? range.upperBound
                        )
                        .tint(theme.accent)
                        // The name belongs on the slider. The heading above it is a
                        // sibling element, so VoiceOver landing on the slider would
                        // otherwise announce a bare percentage and never say which
                        // axis it belongs to.
                        .accessibilityLabel(Text(axis.titleKey, bundle: .module))
                        .accessibilityValue(Self.spoken(model.values.value(of: axis), in: axis.unit))
                    }
                }
            }
        }
    }

    private var alignment: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.axis.textAlignment", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Picker("", selection: alignmentBinding) {
                ForEach(ReaderTextAlignment.allCases, id: \.self) { value in
                    Text(value.titleKey, bundle: .module).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// `reading-themes`: reader-local, and it does not permanently move the
    /// device's own. The reader's value is restored on leaving by `EpubReaderView`.
    private var brightness: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.brightness", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Slider(
                value: Binding(
                    get: { model.brightness ?? Double(UIScreen.main.brightness) },
                    set: { model.brightness = $0 }
                ),
                in: 0.1...1
            ) {
                Text("theme.brightness", bundle: .module)
            } minimumValueLabel: {
                Image(systemName: "sun.min")
            } maximumValueLabel: {
                Image(systemName: "sun.max")
            }
            .tint(theme.accent)
            .accessibilityValue(
                Text(
                    "theme.brightness.percent \(Int(((model.brightness ?? 0.5) * 100).rounded()))",
                    bundle: .module
                )
            )
        }
    }

    private var typefaceBinding: Binding<ReaderTypeface> {
        Binding(
            get: { model.values.typeface },
            set: { new in
                var values = model.values
                values.typeface = new
                model.change(.fontFamily, to: values)
            }
        )
    }

    private var boldBinding: Binding<Bool> {
        Binding(
            get: { model.values.isBold },
            set: { new in
                var values = model.values
                values.isBold = new
                model.change(.boldText, to: values)
            }
        )
    }

    private var alignmentBinding: Binding<ReaderTextAlignment> {
        Binding(
            get: { model.values.textAlignment },
            set: { new in
                var values = model.values
                values.textAlignment = new
                model.change(.textAlignment, to: values)
            }
        )
    }

    private func step(to size: FontSizeStep) {
        var values = model.values
        values.fontSize = size
        model.change(.fontSize, to: values)
    }

    /// What Original costs, said once rather than implied by dead sliders.
    private var publisherNotice: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.publisherStyles.title", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("theme.publisherStyles.reason", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)

            // The single action the spec asks for. It names what it does rather than
            // saying "fix": turning publisher styles off is a real choice about
            // whose typography wins.
            Button { model.leavePublisherStyles() } label: {
                Text("theme.publisherStyles.action", bundle: .module)
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                ForEach(ThemeAxis.allCases.filter(\.requiresPublisherStylesOff), id: \.self) { axis in
                    Text(axis.titleKey, bundle: .module)
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textTertiary)
                }
            }
        }
        .padding(StoryArcSpace.md)
        .background(theme.palette.surfaceRaised, in: .rect(cornerRadius: StoryArcRadius.lg))
    }
}
