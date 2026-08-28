import SwiftUI

internal import DesignSystem
import Kavita
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
    let onOpen: (Publication, URL) -> Void

    @State private var series: [KavitaSeries] = []
    @State private var hasLoaded = false

    private let columns = [GridItem(.adaptive(minimum: 120), spacing: StoryArcSpace.md)]

    var body: some View {
        ScrollView {
            if hasLoaded, series.isEmpty {
                Text("kavita.empty", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                    .padding(StoryArcSpace.gutter)
            }
            LazyVGrid(columns: columns, spacing: StoryArcSpace.md) {
                ForEach(series) { each in
                    NavigationLink {
                        KavitaChapterList(client: client, series: each, onOpen: onOpen)
                    } label: {
                        KavitaSeriesCell(series: each, client: client)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(StoryArcSpace.gutter)
        }
        .background(theme.palette.surfaceCanvas)
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
        return "\(series.name), \(String(localized: "library.cell.progress \(percent)", bundle: .module))"
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
