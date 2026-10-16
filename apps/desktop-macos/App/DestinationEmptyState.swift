import DesignSystem
import LibraryFeature
import SwiftUI

/// What a destination shows before there is anything to show.
///
/// `docs/designs/desktop/README.md` section 7: every empty state names what would be here
/// and offers the one action that fills it, and no illustration comes without an action.
/// Home and Library share the *no sources* page; the one action opens Settings, whose first
/// tab is Sources, because that is where a source is added and the File menu is wave 2.
/// Search's action is the field itself, which the sentence says.
struct DestinationEmptyState: View {
    @Environment(\.theme) private var theme

    let destination: LibraryDestination
    /// Downloads' one action: the library is where a download starts.
    let showLibrary: () -> Void

    var body: some View {
        Group {
            switch destination {
            case .home, .library:
                noSources
            case .onDevice:
                nothingDownloaded
            case .search:
                searchHint
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The content column is the one opaque token surface in this window; the sidebar
        // and toolbar are the system's own material (design section 11).
        .background(theme.palette.surfaceCanvas)
    }

    private var noSources: some View {
        ContentUnavailableView {
            Label("desktop.empty.noSources.title", systemImage: "books.vertical")
        } description: {
            Text("desktop.empty.noSources.body")
        } actions: {
            SettingsLink {
                Text("desktop.empty.noSources.action")
                    .onAccentLabel()
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
        }
    }

    private var nothingDownloaded: some View {
        ContentUnavailableView {
            Label("desktop.empty.downloads.title", systemImage: "arrow.down.circle")
        } description: {
            Text("desktop.empty.downloads.body")
        } actions: {
            Button(action: showLibrary) {
                Text("desktop.empty.downloads.action")
                    .onAccentLabel()
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
        }
    }

    private var searchHint: some View {
        ContentUnavailableView {
            Label("desktop.empty.search.title", systemImage: "magnifyingglass")
        } description: {
            Text("desktop.empty.search.body")
        }
    }
}
