internal import SwiftUI

#if canImport(UIKit)
internal import UIKit
#elseif canImport(AppKit)
internal import AppKit
#endif

internal import Catalogue
internal import DesignSystem
internal import Formats
internal import StoryArcCore

/// What a catalogue says about one publication, and every way it offers to get it.
///
/// `opds-catalog`: the app "selects EPUB for reflowable reading and lets the user choose
/// another format from the publication detail screen". This is that screen. Until it
/// existed the choice lived in a long-press menu — a place a reader has to already know
/// about, offering a decision with none of the context needed to make it.
///
/// The art leads, per the project's rule that the artwork is the interface: the cover at a
/// size worth looking at, and the metadata under it in the order a reader asks for it.
struct CatalogueDetailView: View {
    @Environment(\.theme) private var theme

    let entry: OpdsEntry
    let credential: OpdsCredential?

    /// The page's client, so the cover comes down behind the same credential the feed did.
    let client: OpdsClient

    let queue: DownloadQueue
    let onOpen: (Publication, URL) -> Void

    @State private var cover: Image?

    var body: some View {
        let onDevice = queue.onDevice.contains(entry.id)
        let active = queue.library.pending

        return ScrollView {
            VStack(alignment: .leading, spacing: StoryArcSpace.lg) {
                artwork

                CatalogueDetailHeadline(entry: entry, isDownloaded: onDevice)

                CatalogueFormatChoice(
                    entry: entry,
                    isDownloaded: onDevice,
                    onTake: { link in Task { await take(using: link) } },
                    onRead: { Task { await read() } },
                    onRemove: { queue.remove(entry.id) }
                )

                if let summary = entry.summary, !summary.isEmpty {
                    Text(summary)
                        .textRole(.body)
                        .foregroundStyle(theme.palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let updated = entry.updated {
                    Text(
                        "catalogue.detail.updated \(updated.formatted(date: .abbreviated, time: .omitted))",
                        bundle: .module
                    )
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
                }
            }
            .padding(StoryArcSpace.gutter)
        }
        .background(theme.palette.surfaceCanvas)
        .safeAreaInset(edge: .bottom) {
            if let first = active.first {
                DownloadBanner(
                    download: first,
                    others: active.count - 1,
                    onCancel: { queue.cancel(first.id) },
                    onResume: { queue.resume(first.id) }
                )
            }
        }
        .navigationTitle(entry.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await loadCover() }
    }

    /// The cover, large, with the title standing in for one that never arrives.
    ///
    /// Capped rather than full-bleed: a 2:3 cover across an iPad is a cover nobody can see
    /// the whole of without scrolling, and the metadata under it is the point of the screen.
    @ViewBuilder
    private var artwork: some View {
        HStack {
            Spacer(minLength: 0)

            Group {
                if let cover {
                    cover.resizable().scaledToFill()
                } else {
                    ZStack {
                        theme.palette.surfaceRaised
                        Text(entry.title)
                            .textRole(.headline)
                            .foregroundStyle(theme.palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(StoryArcSpace.md)
                    }
                }
            }
            .frame(maxWidth: StoryArcSpace.huge * 4)
            .aspectRatio(2 / 3, contentMode: .fit)
            .clipShape(.rect(cornerRadius: StoryArcRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: StoryArcRadius.lg)
                    .stroke(theme.palette.borderSubtle, lineWidth: 1)
            )
            // Decorative: the title is read out of the headline below, and a screen reader
            // announcing it twice reads as a stutter.
            .accessibilityHidden(true)

            Spacer(minLength: 0)
        }
    }

    /// Takes the format the app would have picked. The button a reader presses without
    /// thinking about formats at all.
    private func read() async {
        guard let best = CatalogueAcquisition.best(of: entry) else { return }
        await take(using: best)
    }

    /// Fetches one acquisition and hands what came back to the reader.
    ///
    /// An already-downloaded publication opens from disk whichever row was pressed:
    /// `offline-downloads` does not re-fetch what is here, and the queue is the authority on
    /// what that is.
    private func take(using link: OpdsAcquisition) async {
        if let file = queue.downloaded(entry) {
            await open(from: file)
            return
        }
        guard let file = await queue.fetch(entry, using: link) else { return }
        await open(from: file)
    }

    private func open(from file: URL) async {
        guard let publication = try? await PublicationIndexer.index(
            fileAt: file,
            catalogueSeries: entry.series
        ) else { return }
        onOpen(publication, file)
    }

    /// The full-size cover, not the thumbnail the grid settled for.
    private func loadCover() async {
        guard cover == nil, let url = entry.cover ?? entry.thumbnail else { return }
        guard let data = try? await client.data(at: url, credential: credential) else { return }
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return }
        cover = Image(uiImage: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return }
        cover = Image(nsImage: image)
        #endif
    }
}

/// Title, authors, series — the publication's own metadata, as the feed reports it.
struct CatalogueDetailHeadline: View {
    @Environment(\.theme) private var theme

    let entry: OpdsEntry
    let isDownloaded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            if isDownloaded {
                Label {
                    Text("catalogue.entry.downloaded", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.down.circle.fill")
                }
                .textRole(.caption)
                .foregroundStyle(StoryArcColor.Status.success)
            }

            Text(entry.title)
                .textRole(.title2)
                .foregroundStyle(theme.palette.textPrimary)

            if !entry.authors.isEmpty {
                Text(ListFormatter.localizedString(byJoining: entry.authors))
                    .textRole(.subheadline)
                    .foregroundStyle(theme.palette.textSecondary)
            }

            // Written rather than localised: a series name and a number joined by a hash is
            // the same in every language this app speaks, and a two-argument catalogue key
            // is one SwiftUI cannot look up.
            //
            // Composed by ``seriesLine(for:)``, which also decides whether it is worth
            // drawing. This headline used to compose it unconditionally, so an entry titled
            // `Harbour Lights #1` set the title in `title2` and repeated it in `footnote`
            // three lines down — the same defect the grid cell above it had.
            if let series = seriesLine(for: entry) {
                Text(series)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
