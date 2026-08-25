public import SwiftUI

public import Persistence
public import StoryArcCore

internal import DesignSystem

/// Settings, as the seven groups `settings-and-about` names.
///
/// The spec is specific about *why* they are groups: "so that a person can find one
/// without reading all of them", and each summary row "states its current value, so a
/// setting can be checked without entering the group". That second clause is why
/// ``SettingsGroup`` carries a summary at all — seven words would satisfy the first
/// clause and none of the second.
///
/// Two groups are deliberately thin. Sources belongs to the connectors and Downloads to
/// `offline-downloads`; neither exists yet, so both state what they will hold rather than
/// opening onto an empty screen. Saying "not yet" beats a blank page, and beats hiding
/// the group and leaving a reader to wonder where sources live.
public struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Held by the caller, not by this view.
    ///
    /// `settings-and-about` requires an appearance to apply "immediately across the whole
    /// app without a restart", and *immediately* means while the reader is still looking
    /// at the picker. A screen that owned its own copy and handed it back on the way out
    /// would satisfy "without a restart" and fail "immediately".
    @Binding private var settings: AppSettings

    public init(settings: Binding<AppSettings>) {
        _settings = settings
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(SettingsGroup.allCases) { group in
                    NavigationLink {
                        detail(for: group)
                            .navigationTitle(Text(group.titleKey, bundle: .module))
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                                Text(group.titleKey, bundle: .module)
                                Text(group.summaryKey(for: settings), bundle: .module)
                                    .textRole(.footnote)
                                    .foregroundStyle(theme.palette.textSecondary)
                            }
                        } icon: {
                            Image(systemName: group.symbol)
                        }
                    }
                }
            }
            .navigationTitle(Text("settings.title", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("settings.done", bundle: .module) }
                }
            }
        }
    }

    @ViewBuilder
    private func detail(for group: SettingsGroup) -> some View {
        switch group {
        case .appearance: AppearanceSettings(settings: $settings)
        case .reading: ReadingSettings(settings: $settings)
        case .privacy: PrivacySettings()
        case .about: AboutSettings()
        // Named rather than hidden. A group whose rows arrive with a capability that does
        // not exist yet says so.
        case .sources, .downloads, .language:
            List {
                Text(group.pendingKey, bundle: .module)
                    .foregroundStyle(theme.palette.textSecondary)
            }
        }
    }
}
