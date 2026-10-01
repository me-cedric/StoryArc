internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The controls for a badly scanned page, and — since D34 — the two axes
/// `ebook-reader`'s *Fixed-layout EPUB* scenario asks the container itself for.
///
/// `comic-reader`: "brightness, contrast, sharpness, colour inversion, and greyscale ... with
/// a live preview". The preview is the page behind the sheet, which is why this is a sheet
/// with a detent rather than a screen: a control that hides what it changes cannot be judged.
///
/// **Two different brightnesses, on purpose.** The slider above is an image filter: it
/// brightens the pixels this series' pages decode to, kept in `adjustments` and applied
/// before a page is ever drawn. ``brightnessSection`` is the *screen's* backlight, reader-local
/// and reverted on leaving — the same axis `reading-themes` gives the reflowable reader,
/// read from ``ReaderModel/brightness`` rather than from this sheet's own state, because
/// `ReaderBrightness` is what keeps it live across the lifecycle a static binding cannot see.
struct AdjustmentsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @Binding var adjustments: ImageAdjustments

    /// The series the change applies to, named so the reader can see it is not global.
    let shelf: String

    /// Whether the page in front of the reader is being trimmed.
    @Binding var cropsThisPage: Bool

    /// Where the matte and the reader-local brightness live. Read directly rather than
    /// through more bindings: both already belong to the model, and `@Observable` tracks
    /// each read on its own.
    let model: ReaderModel

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

                matteSection
                brightnessSection

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

                // `comic-reader`: "WHEN a user enables border cropping THEN uniform white or
                // black margins are detected and trimmed per page, and the user can disable
                // it for a page that crops wrongly". Two switches, because a reader makes two
                // decisions: the series is trimmed, and this page is the exception to it.
                Section {
                    Toggle(isOn: $adjustments.cropsBorders) {
                        Label {
                            Text("reader.adjust.crop", bundle: .module)
                        } icon: {
                            Image(systemName: "crop")
                        }
                    }
                    // Only where there is a trim to disable. A switch that excuses a page from
                    // nothing offers a choice the reader does not have.
                    if adjustments.cropsBorders {
                        Toggle(isOn: $cropsThisPage) {
                            Label {
                                Text("reader.adjust.crop.thisPage", bundle: .module)
                            } icon: {
                                Image(systemName: "doc")
                            }
                        }
                    }
                } footer: {
                    Text("reader.adjust.crop.note", bundle: .module)
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
                Text(value.wrappedValue.formatted(.percent.precision(.fractionLength(0)).locale(.storyArc)))
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
                Text(value.wrappedValue.formatted(.percent.precision(.fractionLength(0)).locale(.storyArc)))
            )
        }
    }

    /// The colour behind the page. `ReadingDefaults`' own swatches, read live rather than
    /// read as a default: `ReaderMatte.matting(_:over:)` is the same rule either one applies.
    private var matteSection: some View {
        let current = model.settings.theme.custom?.background
        return Section {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 44), spacing: StoryArcSpace.sm)],
                spacing: StoryArcSpace.sm
            ) {
                matteSwatch(nil, isActive: current == nil)
                ForEach(ReaderPalette.suggestedBackgrounds, id: \.self) { hex in
                    matteSwatch(hex, isActive: current?.caseInsensitiveCompare(hex) == .orderedSame)
                }
            }
        } header: {
            Text("reader.matte", bundle: .module)
        } footer: {
            Text("reader.matte.note", bundle: .module)
        }
    }

    private func matteSwatch(_ hex: String?, isActive: Bool) -> some View {
        Button { model.chooseMatte(hex) } label: {
            Circle()
                .fill(hex.flatMap { Color(readerHex: $0) } ?? .black)
                .frame(height: 30)
                .overlay { Circle().strokeBorder(theme.palette.borderSubtle, lineWidth: 1) }
                .overlay {
                    if isActive {
                        Circle().strokeBorder(theme.accent, lineWidth: 3).padding(-4)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(
            hex.map { Text(matteName(for: $0), bundle: .module) }
                ?? Text("reader.matte.none", bundle: .module)
        )
    }

    private func matteName(for hex: String) -> LocalizedStringKey {
        guard let key = ReaderPalette.suggestedBackgroundNames[hex.uppercased()] else {
            return "reader.matte.swatch \(hex)"
        }
        return LocalizedStringKey("reader.matte.\(key)")
    }

    /// `reading-themes`: reader-local, reverted on leaving by `ReaderBrightness` — the same
    /// axis `ThemeAxisSliders.brightness` offers the reflowable reader.
    private var brightnessSection: some View {
        let inForce = model.brightness ?? ReaderBrightness.deviceBrightness
        return Section {
            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Slider(
                    value: Binding(
                        get: { model.brightness ?? ReaderBrightness.deviceBrightness },
                        set: { model.brightness = $0 }
                    ),
                    in: 0.1 ... 1
                ) {
                    Text("reader.brightness", bundle: .module)
                } minimumValueLabel: {
                    Image(systemName: "sun.min")
                } maximumValueLabel: {
                    Image(systemName: "sun.max")
                }
                .tint(theme.accent)
                .accessibilityValue(
                    Text("reader.brightness.percent \(Int((inForce * 100).rounded()))", bundle: .module)
                )
            }
        } header: {
            Text("reader.brightness", bundle: .module)
        }
    }
}
