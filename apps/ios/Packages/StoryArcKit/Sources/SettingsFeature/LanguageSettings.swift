internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The four languages StoryArc speaks, and the option to follow the device.
///
/// `localization`: "a user picks a language in settings", "the whole interface switches
/// immediately without a restart", and "a 'System' option returns to following the device".
/// Immediately is what the environment locale gives: `Bundle.main` is fixed at launch, so
/// nothing here reloads a bundle — every lookup is simply given a different locale.
struct LanguageSettings: View {
    @Environment(\.theme) private var theme

    @Binding var settings: AppSettings

    var body: some View {
        List {
            Section {
                Picker(selection: $settings.language) {
                    Text("settings.language.system", bundle: .module).tag(String?.none)
                    ForEach(InterfaceLanguage.supported, id: \.self) { tag in
                        Text(InterfaceLanguage.name(of: tag)).tag(String?.some(tag))
                    }
                } label: {
                    Text("settings.language", bundle: .module)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("settings.language.note", bundle: .module)
                    .foregroundStyle(theme.palette.textTertiary)
            }
        }
        .navigationTitle(Text("settings.language", bundle: .module))
    }
}
