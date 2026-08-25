internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// Appearance, and the one opt-in that ties it to the reading theme.
///
/// The two are separate by default and the spec says why: "a dark app chrome with a
/// paper-white page is a legitimate preference". The toggle is the "single opt-in setting"
/// the same requirement then allows for readers who want them linked.
struct AppearanceSettings: View {
    @Environment(\.theme) private var theme
    @Binding var settings: AppSettings

    var body: some View {
        List {
            Section {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Button { settings.appearance = mode } label: {
                        HStack(spacing: StoryArcSpace.sm) {
                            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                                Text(mode.localizedNameKey, bundle: .module)
                                    .foregroundStyle(theme.palette.textPrimary)
                                if let note = mode.localizedNoteKey {
                                    Text(note, bundle: .module)
                                        .textRole(.footnote)
                                        .foregroundStyle(theme.palette.textTertiary)
                                }
                            }
                            Spacer()
                            if settings.appearance == mode {
                                Image(systemName: "checkmark").foregroundStyle(theme.accent)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        settings.appearance == mode ? [.isButton, .isSelected] : .isButton
                    )
                }
            }

            Section {
                Toggle(isOn: $settings.linkReadingThemeToAppearance) {
                    VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                        Text("appearance.linkTheme", bundle: .module)
                        Text("appearance.linkTheme.note", bundle: .module)
                            .textRole(.footnote)
                            .foregroundStyle(theme.palette.textTertiary)
                    }
                }
            }
        }
    }
}

/// Reading, which holds less than its name suggests.
///
/// The typographic defaults are not here. `reading-themes` scopes a theme to the series
/// with a global default per scope, and `ShelfMemory` already holds both — so the reading
/// defaults belong to that store and land with task 2.3. What is here is the one reading
/// preference that is neither typographic nor per-series.
struct ReadingSettings: View {
    @Environment(\.theme) private var theme
    @Binding var settings: AppSettings

    var body: some View {
        List {
            Section {
                Toggle(isOn: $settings.turnPagesWithVolumeButtons) {
                    VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                        Text("reading.volumeButtons", bundle: .module)
                        // Off by default and said out loud, because `page-transitions`
                        // asks for the volume buttons "where enabled in settings": volume
                        // keys that silently stop changing the volume are a defect.
                        Text("reading.volumeButtons.note", bundle: .module)
                            .textRole(.footnote)
                            .foregroundStyle(theme.palette.textTertiary)
                    }
                }
            }

            Section {
                Text("reading.defaults.pending", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
            }
        }
    }
}

/// The privacy posture, stated rather than toggled.
///
/// `settings-and-about` asks for this to be "verifiable rather than merely stated", and
/// the reason there is nothing to switch here is the point: the app has no account, no
/// backend and no analytics, so there is nothing to opt out of. A screen full of disabled
/// toggles would imply the opposite.
struct PrivacySettings: View {
    @Environment(\.theme) private var theme

    var body: some View {
        List {
            Section {
                Text("privacy.statement", bundle: .module)
                Text("privacy.sources", bundle: .module)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            Section {
                Text("privacy.pending", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
            }
        }
    }
}
