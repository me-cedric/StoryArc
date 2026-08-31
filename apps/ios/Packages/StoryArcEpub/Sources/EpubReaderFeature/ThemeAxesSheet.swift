public import SwiftUI

internal import DesignSystem
internal import UIKit

public import StoryArcCore

/// Level two of the theme surface: the axes, over the publication's own text.
///
/// `ebook-reader`, *The axes, over the reader's own text*:
///
/// > **THEN** they appear on a surface of their own, over a specimen of the publication's
/// > own text in the active theme, which updates as an axis changes
/// > **AND** every axis states its current value in words or numbers beside its control,
/// > rather than as an unlabelled position on a track
/// > **AND** the axes offered are exactly those in `reading-themes`, with none added and
/// > none dropped
///
/// **Why the split.** Six presets and eleven axes were in one sheet, so a reader who wanted
/// Paper scrolled past nine sliders to find it and a reader who wanted to nudge line spacing
/// hunted for it among the presets. The presets are the common case by a wide margin and
/// they were not what opened first.
///
/// **A second `.sheet`, presented from the first.** Sheet-on-sheet is idiomatic on iOS and
/// the platform animates it as a stack. Android's level two is a destination instead, and
/// `design.md` records that Material does not answer the question directly and which three
/// adjacent rules the decision rests on — chiefly that predictive back is a component-level
/// contract there, so two stacked modal sheets give the gesture two competing dismiss
/// targets and no correct preview.
///
/// The specimen is passed in rather than read again: the reader's position does not move
/// while either sheet is up, and reading the resource a second time would put a disk read
/// inside the transition.
struct ThemeAxesSheet: View {
    @Environment(\.theme) var theme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dismiss) private var dismiss

    let model: EpubReaderModel

    /// Words from where the reader is, read once when level one opened.
    let excerpt: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                    // First, because it is the thing every control below it changes, and
                    // `ebook-reader` asks for it to update "as an axis changes".
                    ThemePreview(
                        readingTheme: model.theme,
                        values: model.values,
                        title: model.chapterTitle,
                        excerpt: excerpt
                    )
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
                    reset
                }
                .padding(StoryArcSpace.gutter)
            }
            .navigationTitle(Text("theme.customise", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("theme.done", bundle: .module) }
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

            // Beside bold rather than among the sliders: both are switches, and
            // `ebook-reader` lists hyphenation with the things a reader adjusts.
            Toggle(isOn: hyphenationBinding) {
                Text("theme.axis.hyphenation", bundle: .module)
                    .textRole(.body)
                    .foregroundStyle(theme.palette.textPrimary)
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

    /// The way back to the preset the reader started from.
    ///
    /// `reading-themes`, *The reset names what it restores*: "the action names that preset —
    /// the reader who modified Calm is offered Calm back, not an unnamed default", and
    /// *Resetting the preset that is already unmodified*: the action is "absent rather than
    /// present and doing nothing, because a control that never changes anything teaches a
    /// reader to distrust the ones that do".
    ///
    /// **A plain low-emphasis button, and no confirmation.** Material has nothing to say
    /// about reset-to-defaults — no component, no pattern — and `design.md` records that
    /// rather than dressing up the Dialogs page's discard-unsaved-changes prompt as one:
    /// that prompt is about abandoning edits, not about restoring defaults. No confirmation
    /// because the reset is immediately reversible by picking the preset again, and a
    /// dialogue over an undoable change is one a reader learns to dismiss unread.
    ///
    /// It does not dismiss the sheet. `reading-themes` asks for the change to be "visible
    /// behind the sheet without the sheet being dismissed", and the specimen above it is the
    /// nearer proof: it repaints as the values go back.
    @ViewBuilder
    private var reset: some View {
        if model.theme.isModified {
            Button {
                model.restoreTheme()
            } label: {
                Text("theme.restore.named \(presetName)", bundle: .module)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .tint(theme.accent)
        }
    }

    /// The active preset's name, as the reset has to say it.
    ///
    /// Resolved to a `String` rather than left as a key, because it is an *argument* to the
    /// sentence: "Restore Calm" is one string with the preset's own name inside it, and a
    /// language that puts the name first has to be able to.
    private var presetName: String {
        String(localized: model.theme.preset.localizedName, bundle: .module)
    }
}
