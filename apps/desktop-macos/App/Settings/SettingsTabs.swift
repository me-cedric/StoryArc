import StoryArcCore
import SwiftUI

/// One tab of the preferences, as a grouped form.
struct SettingsTabContent: View {
    let tab: SettingsTab
    let library: MacLibrary

    var body: some View {
        Form {
            switch tab {
            case .sources: SourcesSettingsTab(library: library)
            case .appearance: AppearanceSettingsTab()
            case .reading: ReadingSettingsTab()
            case .downloads: DownloadsSettingsTab()
            case .language: LanguageSettingsTab()
            case .privacy: PrivacySettingsTab(library: library)
            case .about: AboutSettingsTab()
            }
        }
        .formStyle(.grouped)
    }
}

/// Sources: the folders, each with its state, and the one way to add one.
private struct SourcesSettingsTab: View {
    let library: MacLibrary

    var body: some View {
        Section {
            if library.sources.isEmpty {
                Text("desktop.settings.sources.none").foregroundStyle(.secondary)
            }
            ForEach(library.sources) { source in
                HStack {
                    Image(systemName: "folder").foregroundStyle(source.isGrey ? .secondary : .primary)
                    VStack(alignment: .leading) {
                        Text(source.name).foregroundStyle(source.isGrey ? .secondary : .primary)
                        if source.state == .offline {
                            Text("desktop.settings.sources.offline").scaledFont(.caption).foregroundStyle(.secondary)
                        } else if source.state == .needsAccess {
                            Text("desktop.settings.sources.needsAccess")
                                .scaledFont(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if source.state == .needsAccess {
                        Button { library.repick(source) } label: { Text("desktop.source.chooseAgain") }
                    }
                    Button(role: .destructive) { library.removeFolder(source) } label: {
                        Text("desktop.settings.sources.remove")
                    }
                }
            }
        } header: {
            Text("desktop.settings.sources.folders")
        } footer: {
            Text("desktop.settings.sources.footer").foregroundStyle(.secondary)
        }
        Section {
            Button { library.chooseFolder() } label: { Text("desktop.menu.addFolder") }
        }
    }
}

/// Appearance: the appearance, the accent, the text size.
private struct AppearanceSettingsTab: View {
    var body: some View {
        let settings = MacSettings.shared
        Section {
            Picker(selection: Binding(
                get: { settings.settings.appearance }, set: { settings.settings.appearance = $0 }
            )) {
                Text("desktop.appearance.system").tag(AppearanceMode.system)
                Text("desktop.appearance.light").tag(AppearanceMode.light)
                Text("desktop.appearance.dark").tag(AppearanceMode.dark)
                Text("desktop.appearance.oledDark").tag(AppearanceMode.oledDark)
            } label: { Text("desktop.settings.appearance") }
            Picker(selection: Binding(get: { settings.accent }, set: { settings.accent = $0 })) {
                Text("desktop.accent.brand").tag(ChromeAccent.brand)
                Text("desktop.accent.system").tag(ChromeAccent.system)
            } label: { Text("desktop.accent") }
            Picker(selection: Binding(get: { settings.textSize }, set: { settings.textSize = $0 })) {
                Text("desktop.textSize.default").tag(ChromeTextSize.default)
                Text("desktop.textSize.large").tag(ChromeTextSize.large)
                Text("desktop.textSize.largest").tag(ChromeTextSize.largest)
            } label: { Text("desktop.textSize") }
        } footer: {
            Text("desktop.appearance.footer").foregroundStyle(.secondary)
        }
    }
}

/// Reading: the edge click zones, the spread's cover, the transition that runs.
private struct ReadingSettingsTab: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let settings = MacSettings.shared
        Section {
            Toggle(isOn: Binding(
                get: { settings.settings.turnPagesByTappingTheEdges },
                set: { settings.settings.turnPagesByTappingTheEdges = $0 }
            )) {
                Text("desktop.reading.clickZones")
            }
            Toggle(isOn: Binding(get: { settings.coverAlone }, set: { settings.coverAlone = $0 })) {
                Text("desktop.reader.coverAlone")
            }
        } footer: {
            Text("desktop.reading.clickZones.footer").foregroundStyle(.secondary)
        }
        Section {
            LabeledContent {
                Text(reduceMotion ? "desktop.reading.transition.fade" : "desktop.reading.transition.slide")
            } label: {
                Text("desktop.reading.transition")
            }
        } footer: {
            // *The curl where it is not available*: the settings say why in grey.
            Text(reduceMotion ? "desktop.reading.transition.reduceMotion" : "desktop.reading.transition.curlLater")
                .foregroundStyle(.secondary)
        }
    }
}

/// Downloads: the Wi-Fi rule as "not on a metered link". The queue is wave 3.
private struct DownloadsSettingsTab: View {
    var body: some View {
        let settings = MacSettings.shared
        Section {
            Toggle(isOn: Binding(
                get: { settings.settings.downloadOverWifiOnly },
                set: { settings.settings.downloadOverWifiOnly = $0 }
            )) {
                Text("desktop.downloads.metered")
            }
        } footer: {
            Text("desktop.downloads.footer").foregroundStyle(.secondary)
        }
    }
}

/// Language: the app's own language, apart from the system's.
private struct LanguageSettingsTab: View {
    var body: some View {
        let settings = MacSettings.shared
        Section {
            Picker(selection: Binding(
                get: { settings.settings.language ?? "" },
                set: { tag in
                    settings.settings.language = tag.isEmpty ? nil : tag
                    InterfaceLanguage.choose(settings.settings.language)
                }
            )) {
                Text("desktop.language.system").tag("")
                ForEach(InterfaceLanguage.supported, id: \.self) { tag in
                    Text(InterfaceLanguage.name(of: tag)).tag(tag)
                }
            } label: { Text("desktop.settings.language") }
        } footer: {
            Text("desktop.language.footer").foregroundStyle(.secondary)
        }
    }
}

/// Privacy: what is stored, and the history that can be cleared. The export is wave 3.
private struct PrivacySettingsTab: View {
    let library: MacLibrary

    @State private var isConfirmingClear = false
    @State private var isConfirmingReset = false

    var body: some View {
        Section {
            Text("desktop.privacy.stored").foregroundStyle(.secondary)
            Button(role: .destructive) { isConfirmingClear = true } label: { Text("desktop.privacy.clearHistory") }
                .confirmationDialog(Text("desktop.privacy.clearHistory.title"), isPresented: $isConfirmingClear) {
                    Button(role: .destructive) { clearHistory() } label: { Text("desktop.privacy.clearHistory") }
                } message: {
                    Text("desktop.privacy.clearHistory.body")
                }
        }
        Section {
            Text("desktop.privacy.diagnosticLater").foregroundStyle(.secondary)
        }
        Section {
            Button(role: .destructive) { isConfirmingReset = true } label: { Text("desktop.settings.reset") }
                // `settings-and-about`, *Resetting*: confirmed, and saying what it leaves alone.
                .confirmationDialog(Text("desktop.settings.reset"), isPresented: $isConfirmingReset) {
                    Button(role: .destructive) { MacSettings.shared.reset() } label: {
                        Text("desktop.settings.reset.confirm")
                    }
                } message: {
                    Text("desktop.settings.reset.body")
                }
        }
    }

    private func clearHistory() {
        library.recents.clear()
        NSDocumentController.shared.clearRecentDocuments(nil)
        Task {
            try? await library.progress?.clear()
            await library.refreshProgress()
        }
    }
}
