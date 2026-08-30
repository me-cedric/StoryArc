public import SwiftUI

internal import DesignSystem
internal import Formats
public import Kavita
public import Persistence
public import StoryArcCore

/// A Kavita server's libraries, its series, and the chapters inside them.
///
/// `kavita-server` requires the app to mirror that structure rather than flatten it, so
/// this is three screens rather than one grid: libraries, then series, then chapters.
public struct KavitaBrowserView: View {
    @Environment(\.theme) private var theme

    private let title: String
    private let address: KavitaAddress
    private let sourceId: String
    private let store: KavitaProgressStore
    /// Where a pulled position is written. See `KavitaSync.pull`.
    private let progress: ProgressStore?
    private let lists: [ServerShelf]
    private let onOpen: (Publication, URL) -> Void

    /// Created here, once, from the address.
    ///
    /// Owned rather than made in `init` and held in a `let`: a navigation destination is
    /// re-evaluated whenever the screen behind it redraws, so a client built that way is a
    /// new client each time and the state beside it resets. The catalogue browser learnt
    /// this the same way — a screen that fetched and then showed nothing.
    @State private var client: KavitaClient

    @State private var libraries: [KavitaLibraryFolder] = []
    @State private var failure: String?

    public init(
        title: String,
        address: KavitaAddress,
        sourceId: String,
        store: KavitaProgressStore,
        progress: ProgressStore? = nil,
        lists: [ServerShelf] = [],
        onOpen: @escaping (Publication, URL) -> Void = { _, _ in }
    ) {
        self.title = title
        self.address = address
        self.sourceId = sourceId
        self.store = store
        self.progress = progress
        self.lists = lists
        _client = State(initialValue: KavitaClient(address: address))
        self.onOpen = onOpen
    }

    public var body: some View {
        List {
            if let failure {
                Text(failure)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textPrimary)
            }
            ForEach(libraries) { library in
                NavigationLink {
                    KavitaSeriesList(
                        client: client,
                        library: library,
                        sourceId: sourceId,
                        store: store,
                        progress: progress,
                        lists: lists,
                        onOpen: onOpen
                    )
                } label: {
                    Text(library.name)
                }
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard libraries.isEmpty, failure == nil else { return }
            do {
                libraries = try await client.libraries()
                // Reaching the server is the "next successful connection" the spec retries on.
                await KavitaSync.flush(sourceId, to: address, in: store)
            } catch {
                failure = String(describing: error)
            }
        }
    }
}

/// The series in one library.
