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
            } footer: {
                if scope == ThemeScope.allCases.last {
                    Text("reading.defaults.note", bundle: .module)
                }
            }
        }
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
