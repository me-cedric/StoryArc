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
        onOpen: @escaping (Publication, URL) -> Void = { _, _ in }
    ) {
        self.title = title
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
                    KavitaSeriesList(client: client, library: library, onOpen: onOpen)
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
            } catch {
                failure = String(describing: error)
            }
        }
    }
}

/// The series in one library.
struct KavitaSeriesList: View {
    @Environment(\.theme) private var theme

    let client: KavitaClient
    let library: KavitaLibraryFolder
    let onOpen: (Publication, URL) -> Void

    @State private var series: [KavitaSeries] = []
    @State private var hasLoaded = false

    var body: some View {
        List {
            if hasLoaded, series.isEmpty {
                Text("kavita.empty", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            }
            ForEach(series) { each in
                NavigationLink {
                    KavitaChapterList(client: client, series: each, onOpen: onOpen)
                } label: {
                    VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                        Text(each.name)
                            .foregroundStyle(theme.palette.textPrimary)

                        // `kavita-server`: a series row shows "cover, title, and progress".
                        // The cover needs an authenticated image fetch that does not exist
                        // yet; the progress is what the server already told us.
                        if let fraction = each.fraction {
                            ProgressView(value: fraction)
                                .frame(maxWidth: StoryArcSpace.huge * 2)
                        }
                    }
                }
            }
        }
        .navigationTitle(library.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard !hasLoaded else { return }
            series = (try? await client.series(inLibrary: library.id)) ?? []
            hasLoaded = true
        }
    }
}

/// The volumes and chapters of one series.
struct KavitaChapterList: View {
    @Environment(\.theme) private var theme

    let client: KavitaClient
    let series: KavitaSeries
    let onOpen: (Publication, URL) -> Void

    @State private var volumes: [KavitaVolume] = []
    @State private var fetching: Int?

    var body: some View {
        List {
            ForEach(volumes) { volume in
                Section {
                    ForEach(volume.chapters) { chapter in
                        row(chapter)
                    }
                } header: {
                    // Loose chapters are not a volume, and labelling them as one would
                    // invent a "Volume 0" the server never had.
                    Text(
                        volume.isLooseChapters
                            ? String(localized: "kavita.looseChapters", bundle: .module)
                            : (volume.name ?? "\(volume.number)")
                    )
                }
            }
        }
        .navigationTitle(series.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            guard volumes.isEmpty else { return }
            volumes = (try? await client.volumes(ofSeries: series.id)) ?? []
        }
    }

    @ViewBuilder
    private func row(_ chapter: KavitaChapter) -> some View {
        Button {
            Task { await open(chapter) }
        } label: {
            HStack(spacing: StoryArcSpace.sm) {
                Text(chapter.displayName)
                    .foregroundStyle(theme.palette.textPrimary)

                Spacer(minLength: 0)

                if fetching == chapter.id {
                    ProgressView()
                } else if chapter.isFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(StoryArcColor.Status.success)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(fetching != nil)
    }

    /// Fetches a chapter and hands it to the reader.
    ///
    /// Into the caches directory, not the download store: `kavita-server` and
    /// `offline-downloads` are different promises, and a chapter opened once is not a
    /// download the reader asked to keep.
    private func open(_ chapter: KavitaChapter) async {
        fetching = chapter.id
        defer { fetching = nil }

        guard let data = try? await client.chapter(chapter.id) else { return }
        let directory = URL.cachesDirectory.appending(path: "Kavita", directoryHint: .isDirectory)
        guard (try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )) != nil else { return }

        let file = directory.appending(path: "chapter-\(chapter.id).cbz")
        guard (try? data.write(to: file, options: .atomic)) != nil,
              let publication = try? await PublicationIndexer.index(
                  fileAt: file,
                  seriesHint: series.name
              )
        else { return }
        onOpen(publication, file)
    }
}
