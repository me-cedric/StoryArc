internal import SwiftUI

internal import DesignSystem
internal import Persistence
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
    /// Where the reading *defaults* live. A different store, for the reason 2.3 gives.
    let readerStore: ReaderPreferences

    var body: some View {
        List {
            Section {
                // Stated, not offered. `page-transitions` asks for the volume buttons
                // "where enabled in settings", and on iOS there is no setting that can
                // deliver it: the system owns the volume buttons, and the only way to
                // observe them is to watch `AVAudioSession.outputVolume` — a trick App
                // Review has rejected, and one that breaks the moment something else
                // plays audio.
                //
                // So the row says why rather than pretending. Android has the toggle;
                // `page-transitions` already allows a trigger to be absent where the
                // platform cannot honour it, which is the same clause the curl uses.
                Text("reading.volumeButtons.unavailable", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
            }

            ReadingDefaults(store: readerStore)
        }
    }
}
