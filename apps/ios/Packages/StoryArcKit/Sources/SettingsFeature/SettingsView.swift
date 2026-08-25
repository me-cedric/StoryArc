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

    /// Where the reading *defaults* live. A different store, for the reason 2.3 gives.
    private let readerStore: ReaderPreferences

    /// Returns everything this screen can set to its default, and nothing else.
    private let onReset: () -> Void

    @State private var query = ""
    @State private var isConfirmingReset = false

    public init(
        settings: Binding<AppSettings>,
        readerStore: ReaderPreferences,
        onReset: @escaping () -> Void
    ) {
        _settings = settings
        self.readerStore = readerStore
        self.onReset = onReset
    }

    public var body: some View {
        NavigationStack {
            List {
                let matches = SettingsGroup.search(query)
                if matches.isEmpty {
                    Text("settings.search.empty \(query)", bundle: .module)
                        .foregroundStyle(theme.palette.textSecondary)
                }

                ForEach(matches) { match in
                    NavigationLink {
                        detail(for: match.group)
                            .navigationTitle(Text(match.group.titleKey, bundle: .module))
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                                Text(match.setting ?? match.group.titleKey, bundle: .module)
                                // The group path, which is what makes a match
                                // actionable: a reader who searched "volume" needs to
                                // know it lives under Reading.
                                Text(
                                    match.setting == nil
                                        ? match.group.summaryKey(for: settings)
                                        : match.group.titleKey,
                                    bundle: .module
                                )
                                .textRole(.footnote)
                                .foregroundStyle(theme.palette.textSecondary)
                            }
                        } icon: {
                            Image(systemName: match.group.symbol)
                        }
                    }
                }

                if query.isEmpty {
                    Section {
                        Button(role: .destructive) { isConfirmingReset = true } label: {
                            Text("settings.reset", bundle: .module)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: Text("settings.search", bundle: .module))
            // `settings-and-about`: the app "confirms and states explicitly that sources,
            // downloads, and reading progress are not affected". Naming what survives is
            // the whole job — a confirmation that only says "are you sure" makes a reader
            // guess at the blast radius.
            .confirmationDialog(
                Text("settings.reset", bundle: .module),
                isPresented: $isConfirmingReset,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) { onReset() } label: {
                    Text("settings.reset.confirm", bundle: .module)
                }
            } message: {
                Text("settings.reset.body", bundle: .module)
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
        case .reading: ReadingSettings(settings: $settings, readerStore: readerStore)
        case .privacy: PrivacySettings(settings: settings, readerStore: readerStore)
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
