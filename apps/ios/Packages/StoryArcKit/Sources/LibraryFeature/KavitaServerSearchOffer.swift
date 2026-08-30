import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// The offer to put a running library search to the server it is scoped to.
///
/// **`kavita-server` requires the query to go to the server when the search is within a
/// Kavita source, and this is what that scope was missing.** Narrowing the library to a
/// Kavita server and typing filtered the *local index* — what this device happens to hold —
/// and the server's own search, which reaches chapters, people, genres and tags, was never
/// asked.
///
/// Offered rather than substituted, which is the same shape `library-browsing` already uses
/// for "widen the scope to all sources": the local matches are useful and immediate, and a
/// search that silently left the device for the network would take a reader looking for a
/// downloaded chapter somewhere they did not ask to go.
///
/// Its own file because `LibraryView` is at the line cap. Android's `LibraryScreen` draws
/// the same row above its shelf.
struct KavitaServerSearchOffer: View {
    @Environment(\.theme) private var theme

    let registry: SourceRegistry
    let query: LibraryQuery

    /// Opens the server's own browser with the term already in it.
    let onAsk: (Source) -> Void

    /// The Kavita server this search is scoped to, when it is scoped to one and there is
    /// something to ask.
    private var server: Source? {
        guard let id = query.scope.sourceID,
              let source = registry[id],
              source.kind == .kavitaServer,
              !query.search.trimmingCharacters(in: .whitespaces).isEmpty
        else { return nil }
        return source
    }

    var body: some View {
        if let server {
            Button {
                onAsk(server)
            } label: {
                Text("library.search.onServer \(server.displayName)", bundle: .module)
                    .textRole(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, StoryArcSpace.gutter)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.palette.accent)
        }
    }
}
