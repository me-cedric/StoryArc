import SwiftUI

internal import DesignSystem

/// What a server, catalogue or share shows while it is not answering.
///
/// **This is the honest half of `sources`' "cached contents remain browsable".** That clause
/// holds for a local folder, whose catalogue is written to disk by ``LibraryCache`` and
/// restored before the next walk starts. It does not hold — and deliberately does not — for
/// an OPDS catalogue, a Kavita server or an SMB share: their responses are never written to
/// disk, so there is nothing to browse when the server stops answering.
///
/// Two answers were possible and one had to be chosen. Caching enough of the last good
/// response to browse it means a second catalogue store per source type — feed pages, series
/// lists, chapter lists and their covers — living in a caches directory the system may evict
/// mid-browse, so this screen would still have to exist for the evicted case. It also puts
/// server-supplied URLs on disk, which is the one place an acquisition link's embedded
/// credential could survive a launch. So the app says plainly what is true instead, and the
/// spec scenario was amended to match rather than left describing something no code does.
///
/// What a reader keeps is what they downloaded: those publications are in the library and
/// stay readable, which is what this says rather than leaving them to find out.
struct OfflineSource: View {
    @Environment(\.theme) private var theme

    let name: String

    /// Asks the source again, now. `sources` retries on its own with backoff; this is for a
    /// reader who has just walked back into Wi-Fi range and would rather not wait for it.
    let onRetry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Text("source.offline.title", bundle: .module)
        } description: {
            Text("source.offline.body \(name)", bundle: .module)
        } actions: {
            Button {
                Task { await onRetry() }
            } label: {
                Text("source.offline.retry", bundle: .module)
            }
        }
        .background(theme.palette.surfaceCanvas)
    }
}
