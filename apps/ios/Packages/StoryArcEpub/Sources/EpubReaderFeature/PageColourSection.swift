internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// A reading background of the reader's own, kept legible.
///
/// `reading-themes` asks for four things here and they are easy to build three of:
/// swatches, a picker, a text colour derived at 7:1, and a refusal below 4.5:1
/// **with the measured ratio stated**. The last one is why the ratio is on screen at
/// all times rather than only when something goes wrong — a number that appears only
/// to scold is a number the reader has no reason to trust.
///
/// It is a seventh slot, not a seventh preset: choosing it keeps the typography the
/// reader already has, and tapping one of the six leaves it behind.
///
/// The pairing is described in plain words first and measured second. See
/// ``ReadingComfort``.
///
/// It is also **shown before it is applied**. Every control here sets a pending pairing that
/// the sample, the band and the ratio describe; one confirmation puts it on the page. The
/// refusal is unchanged and still happens on that confirmation, because a pairing has to be
/// asked for before it can be turned down.
struct PageColourSection: View {
    @Environment(\.theme) private var theme

    /// The pairing the page is being drawn with, or nil while the preset's own colours are.
    let inForce: ReaderPalette?

    /// A pairing the reader has chosen and not yet applied.
    ///
    /// `reading-themes` / *Choosing a background* asks for the background and the derived
    /// text colour to be "shown in the preview **before** being applied". Every control here
    /// used to call ``onAdopt`` directly, so the page changed first and the sample under it
    /// drew what was already in force — a preview of the past.
    ///
    /// Owned by ``ThemeAxesSheet`` rather than by this section: the specimen above it draws
    /// the pairing too, and two surfaces previewing one pairing have to agree.
    @Binding var pending: ReaderPalette?

    let onAdopt: (ReaderPalette) -> Bool
    let onDiscard: () -> Void

    /// The ratio of the pairing that was last turned down, so it can be stated.
    @State private var refused: Double?
    @State private var picked = Color.white
    @State private var name = ""

    /// What the sample, the band and the ratio describe.
    private var palette: ReaderPalette? { Self.previewed(pending: pending, inForce: inForce) }

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            Text("theme.pageColour", bundle: .module)
                .textRole(.headline)
                .foregroundStyle(theme.palette.textPrimary)
                // `textRole` sets font and tracking only, so without this the sheet's
                // one long ScrollView offers VoiceOver no heading to jump to.
                .accessibilityAddTraits(.isHeader)

            backgrounds

            ColorPicker(selection: $picked, supportsOpacity: false) {
                Text("theme.pageColour.pick", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            .onChange(of: picked) { _, colour in
                guard let hex = colour.hexString else { return }
                preview(ReaderPalette.derived(name: chosenName, background: hex))
            }

            if let palette {
                inUse(palette)
            }

            if let refused {
                // The band leads here too, so the refusal opens with what the reader
                // can act on rather than with arithmetic.
                band(for: refused)

                // The number, not just the word. `reading-themes`: refused "with the
                // measured ratio stated", because "that is not allowed" without a
                // number is an obstacle rather than an explanation.
                Text(
                    "theme.pageColour.refused \(Self.formatted(refused)) \(Self.formatted(ReadingContrast.aa))",
                    bundle: .module
                )
                .textRole(.footnote)
                // Not the status red: #E94646 on this sheet's near-white material
                // measures 3.87:1, which would put the one sentence that names the
                // contrast floor below it.
                .foregroundStyle(theme.palette.textPrimary)
            }
        }
    }

    // MARK: - Sections

    private var backgrounds: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 44), spacing: StoryArcSpace.sm)],
            spacing: StoryArcSpace.sm
        ) {
            ForEach(ReaderPalette.suggestedBackgrounds, id: \.self) { hex in
                Swatch(
                    hex: hex,
                    isActive: palette?.background.caseInsensitiveCompare(hex) == .orderedSame
                ) {
                    preview(ReaderPalette.derived(name: chosenName, background: hex))
                }
                .accessibilityLabel(Text("theme.pageColour.swatch \(hex)", bundle: .module))
            }
        }
    }

    /// What a pairing will be like to read, said before the number that measures it.
    ///
    /// `textPrimary` against the ratio line's `textSecondary`: the band is the sentence
    /// the reader is meant to read first, and the ratio is the detail under it.
    private func band(for ratio: Double) -> some View {
        Text(LocalizedStringKey(ReadingComfort.band(for: ratio).key), bundle: .module)
            .textRole(.footnote)
            .foregroundStyle(theme.palette.textPrimary)
    }

    /// The pairing in force: what it looks like, what it measures, what to do next.
    private func inUse(_ palette: ReaderPalette) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            sample(palette)

            // The band first, because it is the part a reader can act on, and the
            // measured ratio under it, because the spec keeps the number and a bug
            // report needs it.
            band(for: palette.contrast)

            Text(
                "theme.pageColour.ratio \(Self.formatted(palette.contrast))",
                bundle: .module
            )
            .textRole(.footnote)
            .monospacedDigit()
            .foregroundStyle(theme.palette.textSecondary)

            // `reading-themes`: "a seventh, user-named slot". The name is the
            // reader's, so it is a field rather than something generated for them.
            TextField(
                text: $name,
                prompt: Text("theme.pageColour.name", bundle: .module)
            ) {
                Text("theme.pageColour.name", bundle: .module)
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit { preview(palette.renamed(to: chosenName)) }

            Text("theme.pageColour.textColour", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textSecondary)

            foregrounds(palette)

            // Present only while something is waiting, because a control that never
            // changes anything teaches a reader to distrust the ones that do — the rule
            // `reading-themes` states for the named reset.
            if let pending {
                Button { adopt(pending) } label: {
                    Text("theme.pageColour.apply", bundle: .module)
                }
                .buttonStyle(.borderedProminent)
            }

            Button(role: .destructive) {
                pending = nil
                refused = nil
                onDiscard()
            } label: {
                Text("theme.pageColour.clear", bundle: .module)
            }
            .buttonStyle(.bordered)
        }
    }

    /// Three lines of real text in the pairing, so the reader judges it as text.
    private func sample(_ palette: ReaderPalette) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
            ForEach(0..<3, id: \.self) { _ in
                Text("theme.pageColour.sample", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(Color(hex: palette.foreground))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StoryArcSpace.sm)
        .background(Color(hex: palette.background), in: .rect(cornerRadius: StoryArcRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: StoryArcRadius.sm)
                .strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
        }
        // Read aloud as one thing, and as what it is rather than as three lines of
        // filler a screen reader would otherwise recite.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("theme.pageColour.sample.label", bundle: .module))
    }

    private func foregrounds(_ palette: ReaderPalette) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 44), spacing: StoryArcSpace.sm)],
            spacing: StoryArcSpace.sm
        ) {
            ForEach(ReaderPalette.suggestedForegrounds, id: \.self) { hex in
                Swatch(
                    hex: hex,
                    isActive: palette.foreground.caseInsensitiveCompare(hex) == .orderedSame
                ) {
                    preview(palette.overriding(foreground: hex))
                }
                .accessibilityLabel(Text("theme.pageColour.swatch \(hex)", bundle: .module))
            }
        }
    }

    // MARK: - Previewing, then applying

    /// Shows a pairing without putting it on the page.
    ///
    /// The reader's book keeps the colours it has until they confirm. A refusal from a
    /// previous attempt is cleared, because it measured a pairing that is no longer the one
    /// being described.
    private func preview(_ pairing: ReaderPalette) {
        pending = pairing
        refused = nil
    }

    /// Applies a pairing, or remembers the ratio that stopped it.
    private func adopt(_ candidate: ReaderPalette) {
        guard onAdopt(candidate) else {
            refused = candidate.contrast
            // The reason renders at the foot of the section and the tapped swatch does
            // not move, so without this a VoiceOver user hears nothing and the measured
            // ratio never reaches the reader who was refused.
            //
            // The band is spoken first, in the order the section draws it. A reader who
            // cannot see the sheet is the one who most needs the plain words, and this
            // announcement is the only line that reaches them.
            let ratio = Self.formatted(candidate.contrast)
            let aa = Self.formatted(ReadingContrast.aa)
            let band = String(
                localized: String.LocalizationValue(
                    ReadingComfort.band(for: candidate.contrast).key
                ),
                bundle: .module,
                locale: .storyArc
            )
            let refusal = String(
                localized: "theme.pageColour.refused \(ratio) \(aa)",
                bundle: .module,
                locale: .storyArc
            )
            AccessibilityNotification.Announcement("\(band) \(refusal)").post()
            return
        }
        refused = nil
        // What was pending is now in force, and `inForce` will describe it from here.
        pending = nil
    }

    /// What the sample, the band and the ratio describe.
    ///
    /// The pending pairing where there is one, and the pairing in force otherwise. A
    /// function rather than an expression inside the body, so a host test can ask it —
    /// the precedent ``ThemeSheet/presetColumns(for:)`` sets for the same reason.
    static func previewed(pending: ReaderPalette?, inForce: ReaderPalette?) -> ReaderPalette? {
        pending ?? inForce
    }

    /// The reader's name for the slot, or a default until they give it one.
    private var chosenName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? palette?.name ?? "" : name
    }

    /// The ratio in the reader's own number format: "4,5" where they write a comma.
    private static func formatted(_ ratio: Double) -> String {
        ratio.formatted(.number.precision(.fractionLength(1)).locale(.storyArc))
    }
}

/// What a pairing will be like to read, in words a reader can act on.
///
/// A reader choosing a background colour does not know what "4.7 to 1" means. A number
/// nobody can interpret is not information; it is decoration that looks like
/// information. So the sheet leads with one of three bands and states the measured
/// ratio after it. Nothing is dropped: `reading-themes` requires a refused pairing to
/// be stated "with the measured ratio stated", a reader who is refused deserves to know
/// by how much, and a developer reading a bug report needs the number.
///
/// **The two boundaries are the domain's own, not new ones.** ``ReadingContrast/aaa``
/// at 7, which a derived text colour aims for and every built-in preset clears, and
/// ``ReadingContrast/aa`` at 4.5, below which the sheet refuses the pairing outright. A
/// band drawn at any other number would let the words and the refusal disagree about
/// the same pairing — the sheet calling a pairing comfortable and then refusing it.
///
/// The words are about reading rather than about the numbers behind them, because a
/// reader wants to know whether a chapter will be comfortable, not whether a guideline
/// is met. They replace `theme.pageColour.belowAAA`, which said the same thing in the
/// arithmetic the reader could not read.
///
/// ponytail: it lives beside the one section that draws it rather than in
/// `StoryArcCore`, because it is a wording decision over a number the domain already
/// gives. Move it when a second surface asks the same question.
///
/// Android mirrors this in `PageColourSection.kt`.
enum ReadingComfort: String, CaseIterable {
    /// 7 to 1 and above.
    case easy
    /// 4.5 to 1 up to 7 to 1. Usable, and the sheet says what it costs.
    case tiring
    /// Below 4.5 to 1. Refused.
    case faint

    static func band(for ratio: Double) -> ReadingComfort {
        if ratio >= ReadingContrast.aaa { return .easy }
        return ratio >= ReadingContrast.aa ? .tiring : .faint
    }

    /// The catalogue key that says what this band will be like to read.
    ///
    /// Built from the case name rather than written out three times, so a band cannot
    /// exist without a key. `PageColourBandTests` asserts the catalogue answers each of
    /// them in all four languages, which is the check a literal at the call site would
    /// otherwise buy from `pnpm strings:ios`.
    var key: String { "theme.pageColour.band.\(rawValue)" }
}

/// One colour, tappable, with the selection shown by a ring rather than a tick.
///
/// A tick would have to be one colour or the other and would vanish against half
/// the swatches; a ring in the app's accent never does.
private struct Swatch: View {
    @Environment(\.theme) private var theme

    let hex: String
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Circle()
                .fill(Color(hex: hex))
                .frame(height: 32)
                .overlay {
                    Circle().strokeBorder(theme.palette.borderSubtle, lineWidth: 1)
                }
                .overlay {
                    if isActive {
                        Circle()
                            .strokeBorder(theme.accent, lineWidth: 3)
                            .padding(-4)
                    }
                }
                // The circle stays 32 pt; the target does not. `contentShape` is what
                // widens the tap area — a bare frame leaves it the circle's own path.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

extension ReaderPalette {
    /// The same slot under a different name.
    func renamed(to name: String) -> ReaderPalette {
        ReaderPalette(name: name, background: background, foreground: foreground)
    }
}

extension Color {
    /// `#rrggbb`, or nil if the colour has no sRGB form.
    ///
    /// The picker hands back a `Color`; the domain, Readium and the tokens all speak
    /// hex. This is the one place that converts, so nothing else has to care that a
    /// `Color` is not a number.
    var hexString: String? {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = UIColor(self).cgColor
                  .converted(to: sRGB, intent: .defaultIntent, options: nil),
              let components = converted.components,
              components.count >= 3
        else { return nil }
        let channels = components.prefix(3).map { Int(($0 * 255).rounded()) }
        return "#" + channels.map { String(format: "%02X", $0) }.joined()
    }
}
