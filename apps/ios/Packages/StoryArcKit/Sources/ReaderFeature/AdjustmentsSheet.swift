internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The controls for a badly scanned page.
///
/// `comic-reader`: "brightness, contrast, sharpness, colour inversion, and greyscale ... with
/// a live preview". The preview is the page behind the sheet, which is why this is a sheet
/// with a detent rather than a screen: a control that hides what it changes cannot be judged.
struct AdjustmentsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @Binding var adjustments: ImageAdjustments

    /// The series the change applies to, named so the reader can see it is not global.
    let shelf: String

    /// Whether the page in front of the reader is being trimmed.
    @Binding var cropsThisPage: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    slider(
                        "reader.adjust.brightness",
                        value: $adjustments.brightness,
                        in: -1 ... 1,
                        icon: "sun.max"
                    )
                    slider(
                        "reader.adjust.contrast",
                        value: $adjustments.contrast,
                        in: -1 ... 1,
                        icon: "circle.lefthalf.filled"
                    )
                    slider(
                        "reader.adjust.sharpness",
                        value: $adjustments.sharpness,
                        in: 0 ... 1,
                        icon: "wand.and.rays"
                    )
                }

                Section {
                    Toggle(isOn: $adjustments.isGreyscale) {
                        Label {
                            Text("reader.adjust.greyscale", bundle: .module)
                        } icon: {
                            Image(systemName: "circle.righthalf.filled")
                        }
                    }
                    Toggle(isOn: $adjustments.isInverted) {
                        Label {
                            Text("reader.adjust.invert", bundle: .module)
                        } icon: {
                            Image(systemName: "circle.and.line.horizontal")
                        }
                    }
                } footer: {
                    // Named, because `comic-reader` requires the change to apply "to the
                    // series and [not be] applied globally", and a reader cannot tell the
                    // difference from the controls alone.
                    Text("reader.adjust.scope \(shelf)", bundle: .module)
                        .foregroundStyle(theme.palette.textTertiary)
                }

                Section {
                    Button(role: .destructive) {
                        adjustments = ImageAdjustments()
                    } label: {
                        Text("reader.adjust.reset", bundle: .module)
                    }
                    .disabled(adjustments.isNeutral)
                }
            }
            .navigationTitle(Text("reader.adjust", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("reader.adjust.done", bundle: .module) }
                }
            }
        }
        // Short, so the page stays visible. The preview is the point.
        .presentationDetents([.medium])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    @ViewBuilder
    private func slider(
        _ key: LocalizedStringKey,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        icon: String
    ) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            HStack {
                Label {
                    Text(key, bundle: .module)
                } icon: {
                    Image(systemName: icon)
                }
                Spacer(minLength: 0)
                Text(value.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range) {
                Text(key, bundle: .module)
            }
            // A signed control needs a middle a reader can find without looking. The step
            // is fine enough to be invisible and coarse enough to snap to zero.
            .accessibilityValue(
                Text(value.wrappedValue.formatted(.percent.precision(.fractionLength(0))))
            )
        }
    }
}
