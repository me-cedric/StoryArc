import DesignSystem
import ReaderFeature
import StoryArcCore
import SwiftUI

/// The image adjustments for a badly scanned page, in a popover over the page.
///
/// `comic-reader`, *Adjustments available*, *Cropping borders* and *Persisting adjustments*:
/// brightness, contrast, sharpness, greyscale and inversion with a live preview — the page
/// behind the popover is the preview — and border cropping with a switch that excuses the
/// page in front from it. The change applies to the series, named in the footer, and not
/// globally.
struct AdjustmentsPanel: View {
    let state: ReaderState

    var body: some View {
        Form {
            Section {
                slider("desktop.adjust.brightness", \.brightness, in: -1...1)
                slider("desktop.adjust.contrast", \.contrast, in: -1...1)
                slider("desktop.adjust.sharpness", \.sharpness, in: 0...1)
            }
            Section {
                Toggle(isOn: binding(\.isGreyscale)) { Text("desktop.adjust.greyscale") }
                Toggle(isOn: binding(\.isInverted)) { Text("desktop.adjust.invert") }
            }
            Section {
                Toggle(isOn: binding(\.cropsBorders)) { Text("desktop.adjust.crop") }
                if state.adjustments.cropsBorders {
                    Toggle(isOn: Binding(
                        get: { !state.uncropped.contains(state.shownIndex) },
                        set: { state.setCropsPage(state.shownIndex, $0) }
                    )) {
                        Text("desktop.adjust.cropThisPage")
                    }
                }
            } footer: {
                Text("desktop.adjust.scope \(series)").foregroundStyle(.secondary)
            }
            Section {
                Button { state.setAdjustments(ImageAdjustments()) } label: { Text("desktop.adjust.reset") }
                    .disabled(state.adjustments.isNeutral)
            }
        }
        .formStyle(.grouped)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// What the change applies to: the series, or the publication when it has none.
    private var series: String {
        state.model.publication.series ?? state.model.publication.displayTitle
    }

    private func binding<Value>(_ path: WritableKeyPath<ImageAdjustments, Value>) -> Binding<Value> {
        Binding(
            get: { state.adjustments[keyPath: path] },
            set: { value in
                var next = state.adjustments
                next[keyPath: path] = value
                state.setAdjustments(next)
            }
        )
    }

    private func slider(
        _ key: LocalizedStringKey, _ path: WritableKeyPath<ImageAdjustments, Double>, in range: ClosedRange<Double>
    ) -> some View {
        let value = state.adjustments[keyPath: path]
        let percent = Text(value, format: .percent.precision(.fractionLength(0)))
        return LabeledContent {
            Slider(value: binding(path), in: range) { Text(key) }
                .labelsHidden()
                .frame(width: 150)
                .accessibilityValue(percent)
        } label: {
            HStack {
                Text(key)
                Spacer()
                percent.monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}
