import DesignSystem
import LibraryFeature
import StoryArcCore
import SwiftUI

/// What the content column shows: the search results while text is in the field, else the
/// destination the reader is on.
struct LibraryContentColumn: View {
    @Environment(\.theme) private var theme

    let library: MacLibrary
    let search: SearchState
    let destination: LibraryDestination
    let filter: LibraryShelfFilter
    @Binding var selection: LibrarySelection
    let onOpen: (Publication) -> Void
    let onShow: (Publication) -> Void

    var body: some View {
        VStack(spacing: 0) {
            LibraryNotices(library: library, onOpen: onOpen)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The content column is the one opaque token surface in this window; the sidebar
        // and toolbar are the system's own material (design section 11).
        .background(theme.palette.surfaceCanvas)
        .onChange(of: search.text, initial: true) { _, text in
            var query = library.model.query
            query.search = text
            library.model.query = query
        }
    }

    @ViewBuilder
    private var content: some View {
        if search.isShowingResults {
            results
        } else if library.sources.isEmpty, library.model.publications.isEmpty {
            DestinationEmptyState(destination: destination, showLibrary: {})
        } else {
            switch destination {
            case .home:
                HomeView(library: library, onOpen: onOpen, onShow: onShow)
            case .library:
                shelf(library.model.visible)
            case .onDevice:
                DestinationEmptyState(destination: .onDevice, showLibrary: {})
            case .search:
                SearchAtRestView(library: library)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if library.model.visible.isEmpty {
            ContentUnavailableView.search(text: search.text)
        } else {
            shelf(library.model.visible)
        }
    }

    @ViewBuilder
    private func shelf(_ publications: [Publication]) -> some View {
        let shown = filter.apply(publications, model: library.model)
        if shown.isEmpty, library.model.query.isNarrowed {
            ContentUnavailableView {
                Label("desktop.library.filtered.title", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("desktop.library.filtered.body")
            } actions: {
                Button { library.model.clearFilters() } label: { Text("desktop.library.filtered.clear") }
            }
        } else if library.model.layout == .list {
            CoverListView(library: library, publications: shown, selection: $selection, onOpen: onOpen, onShow: onShow)
        } else {
            CoverGridView(
                library: library, publications: shown, groupSeries: filter == .series,
                selection: $selection, onOpen: onOpen, onShow: onShow
            )
        }
    }
}

extension LibraryShelfFilter {
    /// The shelf through this sidebar filter.
    func apply(_ publications: [Publication], model: LibraryModel) -> [Publication] {
        switch self {
        case .all, .series: publications
        case .recentlyAdded:
            publications.filter { $0.addedAt != nil }
                .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
        }
    }
}

/// What the search destination shows before a letter is typed: the recent searches.
struct SearchAtRestView: View {
    let library: MacLibrary

    var body: some View {
        let recents = library.model.recentSearches.terms
        if recents.isEmpty {
            DestinationEmptyState(destination: .search, showLibrary: {})
        } else {
            List {
                Section("desktop.search.recent") {
                    ForEach(recents, id: \.self) { term in
                        Button(term) {
                            var query = library.model.query
                            query.search = term
                            library.model.query = query
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button { library.model.clearRecentSearches() } label: { Text("desktop.search.clearRecent") }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

/// The grey lines above the shelf: what could not be opened, what could not be restored,
/// what was dropped past the window limit, and the folders that need access.
struct LibraryNotices: View {
    @Environment(\.theme) private var theme

    let library: MacLibrary
    let onOpen: (Publication) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(library.sources.filter(\.isGrey)) { source in
                notice(Self.sentence(for: source)) {
                    if source.state == .needsAccess {
                        Button { library.repick(source) } label: { Text("desktop.source.chooseAgain") }
                    }
                }
            }
            if !library.couldNotRestore.isEmpty {
                notice("desktop.restore.missing \(library.couldNotRestore.map(\.title).joined(separator: ", "))") {
                    Button { library.dismissCouldNotRestore() } label: { Text("desktop.notice.dismiss") }
                }
            }
            ForEach(library.refused) { refused in
                notice(RefusedFileWords.sentence(for: refused)) {
                    Button { library.dismissRefused() } label: { Text("desktop.notice.dismiss") }
                }
            }
            if !library.listedForLater.isEmpty {
                let listed = library.listedForLater.map(\.title).joined(separator: ", ")
                notice("desktop.drop.listed \(OpenBatch.windowLimit) \(listed)") {
                    Button { library.dismissListed() } label: { Text("desktop.notice.dismiss") }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, library.sources.contains(where: \.isGrey) || !library.refused.isEmpty
                 || !library.couldNotRestore.isEmpty || !library.listedForLater.isEmpty ? 8 : 0)
    }

    private static func sentence(for source: FolderSource) -> LocalizedStringKey {
        source.state == .offline ? "desktop.source.offline \(source.name)" : "desktop.source.needsAccess \(source.name)"
    }

    private func notice(_ text: LocalizedStringKey, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
            Text(text).lineLimit(2)
            Spacer()
            action().controlSize(.small)
        }
        .scaledFont(.callout)
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(theme.palette.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The sentence for a refusal, in `local-library`'s words. A Mac copy of `RefusedFile.message`.
enum RefusedFileWords {
    static func sentence(for refused: RefusedFile) -> LocalizedStringKey {
        switch refused.outcome {
        case .contentProtected: "desktop.refused.protected \(refused.name)"
        case .passwordProtected: "desktop.refused.passwordProtected \(refused.name)"
        case .solidArchive: "desktop.refused.solidArchive \(refused.name)"
        case .damaged: "desktop.refused.damaged \(refused.name)"
        case let .unsupported(detected):
            "desktop.refused.unsupported \(refused.name) \(detected) \(RefusedFile.supported)"
        case .unreadable, .opened: "desktop.refused.unreadable \(refused.name) \(RefusedFile.supported)"
        }
    }
}
