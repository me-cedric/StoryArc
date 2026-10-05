import SwiftUI

internal import DesignSystem
import Kavita
import Persistence
import StoryArcCore

/// A Kavita library's series, as covers.
///
/// `kavita-server` asks for "cover, title, and progress". A list of names would satisfy the
/// words and none of the point: a comic library is recognised by its covers, and a reader
/// scanning for one is looking at pictures.
struct KavitaSeriesList: View {
    @Environment(\.theme) private var theme

    let client: KavitaClient
    let library: KavitaLibraryFolder
    /// The server's one search, carried down from the browser above. See ``KavitaFinder``.
    let finder: KavitaFinder
    let sourceId: String
    let store: KavitaProgressStore
    /// `library-browsing`'s *A publication's actions wherever it is drawn* names "a server's
    /// own browser" — carried down to ``KavitaChapterList``.
    let model: LibraryModel
    /// Where a pulled position is written. See `KavitaSync.pull`.
    var progress: ProgressStore?
    /// This server's own reading lists, passed through to each chapter list.
    var lists: [ServerShelf] = []
    let onOpen: (Publication, URL) -> Void

    @State private var series: [KavitaSeries] = []
    @State private var hasLoaded = false

    /// Why the list is empty, when it is empty for a reason.
    ///
    /// This used to be a `try?` into an empty array, so a server too old to answer the
    /// listing at all looked exactly like a library with nothing in it. A reader on such a
    /// server deserves the sentence, not a silent empty shelf.
    @State private var failure: String?

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: StoryArcSpace.md)]

    /// A couple of rows' worth, whatever the column count: the grid never needs to scroll
    /// either.
    private static let placeholderCells = 10

    var body: some View {
        Group {
            if finder.isShowing {
                KavitaHits(
                    finder: finder,
                    client: client,
                    sourceId: sourceId,
                    store: store,
                    model: model,
                    progress: progress,
                    lists: lists,
                    onOpen: onOpen
                )
            } else {
                covers
            }
        }
        .navigationTitle(library.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .kavitaSearchable(finder) { await finder.run(client, sourceId: sourceId) }
        .task {
            guard !hasLoaded else { return }
            do {
                series = try await client.series(inLibrary: library.id)
                failure = nil
            } catch {
                failure = KavitaMessage.of(error, source: library.name)
            }
            hasLoaded = true
        }
    }

    private var covers: some View {
        ScrollView {
            if let failure {
                Text(failure)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textPrimary)
                    .padding(StoryArcSpace.gutter)
            } else if hasLoaded, series.isEmpty {
                Text("kavita.empty", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                    .padding(StoryArcSpace.gutter)
            }
            LazyVGrid(columns: columns, spacing: StoryArcSpace.md) {
                // `native-experience` asks for no blocking spinner while the server answers:
                // cells shaped like the covers about to arrive, rather than a blank grid.
                if kavitaShowsSeriesPlaceholders(failure: failure, hasLoaded: hasLoaded) {
                    ForEach(0 ..< Self.placeholderCells, id: \.self) { _ in
                        KavitaSeriesCellPlaceholder()
                    }
                }
                ForEach(series) { each in
                    NavigationLink {
                        KavitaChapterList(
                            client: client,
                            series: each,
                            sourceId: sourceId,
                            store: store,
                            model: model,
                            progress: progress,
                            lists: lists,
                            onOpen: onOpen
                        )
                    } label: {
                        KavitaSeriesCell(series: each, client: client)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(StoryArcSpace.gutter)
        }
        .background(theme.palette.surfaceCanvas)
    }
}

/// One series, as a cover with its title and progress under it.
struct KavitaSeriesCell: View {
    @Environment(\.theme) private var theme

    let series: KavitaSeries
    let client: KavitaClient

    @State private var cover: Image?

    /// Progress worth drawing. A bar at zero says "started" about a series nobody has opened.
    private var read: Double? {
        guard let fraction = series.fraction, fraction > 0 else { return nil }
        return fraction
    }

    private var spoken: String {
        guard let read else { return series.name }
        let percent = Int(read * 100)
        let progress = String(localized: "library.cell.progress \(percent)", bundle: .module, locale: .storyArc)
        return "\(series.name), \(progress)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: StoryArcRadius.md)
                    .fill(theme.palette.surfaceRaised)
                if let cover {
                    cover
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: StoryArcRadius.md))
                } else {
                    Text(series.name)
                        .textRole(.caption)
                        .foregroundStyle(theme.palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(StoryArcSpace.sm)
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipped()

            Text(series.name)
                .textRole(.body)
                .foregroundStyle(theme.palette.textPrimary)
                .lineLimit(2)

            if let read {
                ProgressView(value: read)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        // Through the client, not an image loader: Kavita's image routes want the reader's
        // key, and a loader has nowhere to put one.
        .task(id: series.id) {
            guard cover == nil, let data = try? await client.seriesCover(series.id) else { return }
            cover = Self.image(from: data)
        }
    }

    private static func image(from data: Data) -> Image? {
        #if canImport(UIKit)
        return UIImage(data: data).map(Image.init(uiImage:))
        #elseif canImport(AppKit)
        return NSImage(data: data).map(Image.init(nsImage:))
        #else
        return nil
        #endif
    }
}

/// Whether the series grid draws placeholder cells in place of the real one.
///
/// Pulled out beside the view — same reason as ``detailSummary(of:)`` in
/// `DetailAbsences.swift`: free and pure so `KavitaWaitingTests` can assert it without a
/// view. The server has been asked and has not answered, and there is no failure to show
/// instead.
func kavitaShowsSeriesPlaceholders(failure: String?, hasLoaded: Bool) -> Bool {
    failure == nil && !hasLoaded
}

/// Drawn in place of a series cover while the server has been asked and has not answered.
///
/// Shaped like ``KavitaSeriesCell``'s own cover tile — same corner radius, same 2:3 aspect
/// ratio — so a reader sees a grid filling in rather than a different kind of grid.
struct KavitaSeriesCellPlaceholder: View {
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: StoryArcRadius.md)
            .fill(theme.palette.surfaceRaised)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
    }
}
