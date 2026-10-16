import SwiftUI

/// The preferences window: one window, toolbar tabs, grouped forms, and a search.
///
/// The six tabs are the design's (section 5) and match the spec groups. The search field
/// the spec asks for lists the settings that match under their tabs and opens the tab of
/// the one chosen; an empty result says so in grey. A reading setting changed here applies
/// to an open reader at once, because every window reads `MacSettings.shared`. Task 2.21.
struct SettingsRoot: View {
    /// Fixed by the design: "Width 560 pt fixed."
    static let width: CGFloat = 560

    let library: MacLibrary

    @State private var tab: SettingsTab = .sources
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                tabs
            } else {
                SettingsSearchResults(query: query) { entry in
                    tab = entry.tab
                    query = ""
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: Text("desktop.settings.search"))
        .frame(width: Self.width)
        .frame(minHeight: 320)
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            ForEach(SettingsTab.allCases) { tab in
                Tab(LocalizedStringKey(tab.titleKey), systemImage: tab.symbolName, value: tab) {
                    SettingsTabContent(tab: tab, library: library)
                }
            }
        }
    }
}

/// What a search shows: the matching settings under their tabs, or one grey sentence.
struct SettingsSearchResults: View {
    let query: String
    let onChoose: (SettingsEntry) -> Void

    var body: some View {
        let groups = SettingsIndex.grouped(query)
        if groups.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(groups, id: \.tab) { group in
                    Section(LocalizedStringKey(group.tab.titleKey)) {
                        ForEach(group.entries) { entry in
                            Button { onChoose(entry) } label: {
                                HStack {
                                    Text(entry.title)
                                    Spacer()
                                    Text(LocalizedStringKey(group.tab.titleKey)).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
