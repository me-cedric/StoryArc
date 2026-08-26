internal import SwiftUI

internal import DesignSystem
internal import Persistence
internal import StoryArcCore

/// What a series never opened before is read with.
///
/// `settings-and-about`: "it applies to publications opened from then on and does not
/// overwrite a per-series choice already made". That second clause needs no code here —
/// ``ShelfMemory/settingDefault(_:for:)`` writes to a different dictionary than the
/// per-shelf entries, so it *cannot* reach one. The guarantee is structural rather than
/// careful.
///
/// Two scopes, because `reading-themes` gives comics and reflowable text separate defaults
/// and means it: a reader who wants cream paper for novels may well want black behind a
/// comic.
///
/// Names rather than the reader's preset *cards*. A card previews a theme in its own
/// colours and typeface, which is worth the space when the page is visible behind it and
/// is six swatches of decoration in a settings list.
struct ReadingDefaults: View {
    @Environment(\.theme) private var theme

    let store: ReaderPreferences

    /// Re-read after each change so the ticks follow. The reader owns these while it is
    /// open; nothing else is writing them here.
    @State private var memory: ShelfMemory

    init(store: ReaderPreferences) {
        self.store = store
        _memory = State(initialValue: store.themes())
    }

    var body: some View {
        ForEach(ThemeScope.allCases, id: \.self) { scope in
            Section {
                ForEach(ThemePreset.allCases, id: \.self) { preset in
                    Button { choose(preset, for: scope) } label: {
                        HStack {
                            Text(preset.settingsTitleKey, bundle: .module)
                                .foregroundStyle(theme.palette.textPrimary)
                            Spacer()
                            if memory.default(for: scope).theme.preset == preset {
                                Image(systemName: "checkmark").foregroundStyle(theme.accent)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        memory.default(for: scope).theme.preset == preset
                            ? [.isButton, .isSelected] : .isButton
                    )
                }
            } header: {
                Text(scope.titleKey, bundle: .module)
            }

            if scope == .fixedLayout {
                comicMatte
            }
        }

        Section {
            Text("reading.defaults.note", bundle: .module)
                .textRole(.footnote)
                .foregroundStyle(theme.palette.textTertiary)
        }
    }

    /// The colour behind a comic page.
    ///
    /// `reading-themes`: a custom background "applies to the area around the page and not to
    /// the page itself, because tinting artwork is not a reading preference". A comic has no
    /// typography for a preset to change, so what a preset offers it is only its paper
    /// colour — and that is not what a preset means. This is the colour, on its own.
    ///
    /// Swatches only. The reader's own picker, with its sliders and its contrast refusal,
    /// lives in the *reader*, where the page is visible behind it and a choice can be
    /// judged. Here there is nothing to judge it against, and every suggested background
    /// clears AAA already, so a picker would offer a refusal path with no way to see why.
    private var comicMatte: some View {
        let current = memory.default(for: .fixedLayout).theme.custom?.background
        return Section {
            // A grid rather than a row: nine swatches sharing one row leaves each of them
            // under the 44 pt touch floor, and wrapping is what buys the width back.
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 44), spacing: StoryArcSpace.sm)],
                spacing: StoryArcSpace.sm
            ) {
                // Black first: it is the default, and "none" has to be reachable or a
                // reader who tries a colour is stuck with one.
                matteSwatch(nil, isActive: current == nil)
                ForEach(ReaderPalette.suggestedBackgrounds, id: \.self) { hex in
                    matteSwatch(hex, isActive: current?.caseInsensitiveCompare(hex) == .orderedSame)
                }
            }
        } header: {
            Text("reading.matte", bundle: .module)
        } footer: {
            Text("reading.matte.note", bundle: .module)
        }
    }

    private func matteSwatch(_ hex: String?, isActive: Bool) -> some View {
        Button { chooseMatte(hex) } label: {
            Circle()
                .fill(hex.flatMap { Color(settingsHex: $0) } ?? .black)
                .frame(height: 30)
                .overlay { Circle().strokeBorder(theme.palette.borderSubtle, lineWidth: 1) }
                .overlay {
                    if isActive {
                        Circle().strokeBorder(theme.accent, lineWidth: 3).padding(-4)
                    }
                }
                // A plain button is hit only inside its label, and the drawn circle is
                // 30 pt. The ring above paints outside the frame and adds no hit area.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        // The hex inside a labelled template, the reader's own swatch convention — a
        // bare "#E8EFE6" is a puzzle read out one character at a time. And localised,
        // which the bare literal was not.
        .accessibilityLabel(
            hex.map { Text(matteName(for: $0), bundle: .module) }
                ?? Text("reading.matte.none", bundle: .module)
        )
    }

    /// The string key for a suggested background's name.
    ///
    /// The colour's name, not its hex. VoiceOver read "Colour #E8EFE6" one character at a
    /// time, which is not a colour a reader can pick out of a row of nine. The names live
    /// in `ReaderPalette` so Android calls the same colour the same thing.
    private func matteName(for hex: String) -> LocalizedStringKey {
        guard let key = ReaderPalette.suggestedBackgroundNames[hex.uppercased()] else {
            // A colour added to the list without a name still announces something the
            // reader can act on, rather than nothing.
            return "reading.matte.swatch \(hex)"
        }
        return LocalizedStringKey("reading.matte.\(key)")
    }

    private func chooseMatte(_ hex: String?) {
        let existing = memory.default(for: .fixedLayout)
        var updatedTheme = existing.theme
        if let hex {
            updatedTheme = updatedTheme.adopting(ReaderPalette.derived(name: hex, background: hex))
        } else {
            updatedTheme = updatedTheme.discardingCustomColours()
        }
        var stored = existing
        stored.theme = updatedTheme
        let updated = store.themes().settingDefault(stored, for: .fixedLayout)
        store.save(updated)
        memory = updated
    }

    private func choose(_ preset: ThemePreset, for scope: ThemeScope) {
        // The whole settings value, not just the preset: a preset carries its own
        // typography, and a default that kept the previous one would not be the preset
        // the reader chose.
        let stored = ShelfSettings(theme: ReadingTheme(preset: preset), values: preset.values)
        let updated = store.themes().settingDefault(stored, for: scope)
        store.save(updated)
        memory = updated
    }
}

extension ThemeScope {
    /// How the two scopes are named on screen.
    var titleKey: LocalizedStringKey {
        switch self {
        case .reflowable: "reading.defaults.reflowable"
        case .fixedLayout: "reading.defaults.fixed"
        }
    }
}

extension ThemePreset {
    /// How the six presets are named here.
    ///
    /// A second copy of the reader's list. The alternative is a shared localisation target
    /// for six words, and `reading-themes` names them in the spec rather than in code — so
    /// the duplication is of a translation, not of a decision.
    var settingsTitleKey: LocalizedStringKey {
        switch self {
        case .original: "preset.original"
        case .quiet: "preset.quiet"
        case .paper: "preset.paper"
        case .bold: "preset.bold"
        case .calm: "preset.calm"
        case .focus: "preset.focus"
        }
    }
}
