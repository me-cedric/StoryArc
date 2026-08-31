internal import SwiftUI

internal import DesignSystem
internal import UIKit

internal import StoryArcCore

// The sliders on level two, and the row that states what each one is set to.
//
// `reading-themes`, *Every axis states its value*: "its current value is stated beside it in
// the reader's own language and units, and updates as the control moves **AND** the value is
// available to assistive technology as part of the control rather than as a separate
// unlabelled element."
//
// Split out of `ThemeAxesSheet.swift` because that file reached this project's 400-line
// ceiling once level two became a file of its own — and the seam is the right one: everything
// here is a continuous axis with a value to say, and what is left there is the sheet's
// structure plus the two pickers and the notice.
//
// The members are internal rather than private because `ThemeAxesSheet.body` is in the other
// file, and a `private` member of an extension cannot be reached from it.
extension ThemeAxesSheet {
    /// A slider's value as a screen reader should say it.
    ///
    /// The unit comes from the domain, so the two platforms cannot describe the same
    /// slider differently. The number is formatted for the reader's locale, which is
    /// why this is not a plain interpolation — a comma decimal separator is not a
    /// detail a French reader should have to work around.
    static func spoken(_ value: Double, in unit: AxisUnit?) -> Text {
        let number = value.formatted(.number.precision(.fractionLength(0...2)))
        switch unit {
        case .multiple: return Text("theme.axis.value.multiple \(number)", bundle: .module)
        case .em: return Text("theme.axis.value.em \(number)", bundle: .module)
        case nil: return Text(verbatim: number)
        }
    }

    /// The sliders. One loop rather than five blocks, because the domain answers
    /// every question a slider asks: its range, its value, and how to set it.
    var fineAxes: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.md) {
            Text("theme.spacing", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(ThemeAxis.allCases, id: \.self) { axis in
                if let range = axis.sliderRange {
                    VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                        axisHeader(
                            Text(axis.titleKey, bundle: .module),
                            value: Self.spoken(model.values.value(of: axis), in: axis.unit)
                        )

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

    /// `reading-themes`: reader-local, and it does not permanently move the
    /// device's own. The reader's value is restored on leaving by `EpubReaderView`.
    var brightness: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            axisHeader(
                Text("theme.brightness", bundle: .module),
                value: Text(
                    "theme.brightness.percent \(Int(((model.brightness ?? 0.5) * 100).rounded()))",
                    bundle: .module
                ),
                isSectionHeading: true
            )

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

    /// An axis's name on the left, its current value on the right.
    ///
    /// `reading-themes`, *Every axis states its value*:
    ///
    /// > **THEN** its current value is stated beside it in the reader's own language and
    /// > units, and updates as the control moves
    /// > **AND** the value is available to assistive technology as part of the control rather
    /// > than as a separate unlabelled element
    ///
    /// **So the visible value is hidden from assistive technology, and the control carries
    /// it.** Both halves of that requirement are load-bearing in opposite directions: a
    /// reader has to *see* the number, and a screen reader has to hear it once, from the
    /// slider, where an adjust gesture will change it. A visible label left visible to
    /// VoiceOver is the "separate unlabelled element" the requirement names — it lands
    /// between the axis's name and its slider and reads a bare number.
    ///
    /// The slider's own `.accessibilityValue` is the other half, and it is next to every
    /// call site rather than here: it belongs to the control.
    @ViewBuilder
    func axisHeader(_ name: Text, value: Text, isSectionHeading: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            name
                .textRole(isSectionHeading ? .headline : .footnote)
                .foregroundStyle(
                    isSectionHeading ? theme.palette.textPrimary : theme.palette.textSecondary
                )
                .accessibilityAddTraits(isSectionHeading ? .isHeader : [])

            Spacer(minLength: StoryArcSpace.sm)

            value
                .textRole(.footnote)
                .monospacedDigit()
                .foregroundStyle(theme.palette.textTertiary)
                .accessibilityHidden(true)
        }
    }
}
