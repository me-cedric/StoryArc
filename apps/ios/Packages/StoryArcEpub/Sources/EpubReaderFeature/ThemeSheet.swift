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
/// The fine axes — line, character, word and paragraph spacing, margins, alignment,
/// custom background — are Phase 3.5 and 3.7 of the change and are not here yet.
/// What is here is the first level the spec describes.
struct ThemeSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    let model: EpubReaderModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                    presets
                    fontSize
                    typeface
                    if model.theme.preset.keepsPublisherStyles {
                        publisherNotice
                    } else {
                        fineAxes
                        alignment
                    }
                    brightness
                }
                .padding(StoryArcSpace.gutter)
            }
            .background(theme.palette.surfaceCanvas)
            .navigationTitle(Text("theme.title", bundle: .module))
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

            LazyVGrid(
                columns: Array(repeating: GridItem(spacing: StoryArcSpace.sm), count: 3),
                spacing: StoryArcSpace.sm
            ) {
                ForEach(ThemePreset.allCases, id: \.self) { preset in
                    PresetCard(
                        preset: preset,
                        isActive: model.theme.preset == preset,
                        isModified: model.theme.preset == preset && model.theme.isModified
                    ) {
                        model.adopt(preset)
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
        .accessibilityValue(
            Text("theme.fontSize.percent \(model.values.fontSize.rawValue)", bundle: .module)
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

            // A menu, not a segmented control: eight faces will not fit across a
            // phone, and `reading-themes` calls this axis a picker.
            Picker("", selection: typefaceBinding) {
                ForEach(ReaderTypeface.allCases, id: \.self) { face in
                    if face.isDesignedForLowVision {
                        // `reading-themes`: labelled as such, because "an
                        // accessibility affordance presented as a style option gets
                        // missed by the people who need it".
                        VStack(alignment: .leading) {
                            Text(face.titleKey, bundle: .module)
                            Text("theme.typeface.lowVision", bundle: .module)
                        }
                        .tag(face)
                    } else {
                        Text(face.titleKey, bundle: .module).tag(face)
                    }
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Toggle(isOn: boldBinding) {
                Text("theme.axis.boldText", bundle: .module)
                    .textRole(.body)
                    .foregroundStyle(theme.palette.textPrimary)
            }
        }
    }

    /// The sliders. One loop rather than five blocks, because the domain answers
    /// every question a slider asks: its range, its value, and how to set it.
    private var fineAxes: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            Text("theme.spacing", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)

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
                            in: range
                        )
                        .tint(theme.accent)
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
