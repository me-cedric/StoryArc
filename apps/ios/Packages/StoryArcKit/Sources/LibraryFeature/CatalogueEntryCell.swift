public import SwiftUI

#if canImport(UIKit)
internal import UIKit
#elseif canImport(AppKit)
internal import AppKit
#endif

internal import Catalogue
internal import DesignSystem
internal import StoryArcCore

/// One publication in a catalogue, before it is on the device.
///
/// Not a ``CoverCell``: that one shows reading progress and a format for something the
/// reader owns, and this shows whether the thing can be read at all. `opds-catalog`
/// requires an entry offering only unsupported formats to be "listed but marked
/// unreadable, naming the formats offered", which is a state a local publication never has.
struct CatalogueEntryCell: View {
    @Environment(\.theme) private var theme

    let entry: OpdsEntry
    let credential: OpdsCredential?

    /// The page's client, not one of this cell's own. A session per cell is a session per
    /// cell to tear down, and a grid makes plenty of both.
    let client: OpdsClient

    /// Whether this one is already on the device.
    let isDownloaded: Bool

    @State private var cover: Image?

    /// The formats this entry offers that StoryArc can open.
    private var readable: [OpdsAcquisition] {
        entry.acquisitions.filter { acquisition in
            guard acquisition.kind.isFetchable else { return false }
            return PublicationFormat(mediaType: acquisition.mediaType)?.isOpenable == true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.sm) {
            artwork
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: StoryArcRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: StoryArcRadius.md)
                        .stroke(theme.palette.borderSubtle, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                // `offline-downloads`: a downloaded publication shows "a state indicator"
                // rather than an action to download it again.
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
                    .textRole(.subheadline)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(2)

                Text(subtitle)
                    .textRole(.caption)
                    .foregroundStyle(readable.isEmpty ? StoryArcColor.Status.offline : theme.palette.textSecondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .task(id: entry.id) { await loadCover() }
    }

    /// The author, or — when nothing here can be opened — what was offered instead.
    private var subtitle: String {
        guard readable.isEmpty else {
            return entry.series.map { series in
                entry.seriesIndex.map { "\(series) #\(Int($0))" } ?? series
            } ?? entry.authors.first ?? ""
        }
        let offered = entry.acquisitions.map(\.mediaType).filter { !$0.isEmpty }
        guard !offered.isEmpty else {
            return String(localized: "catalogue.entry.noDownload", bundle: .module, locale: .storyArc)
        }
        return String(
            format: String(localized: "catalogue.entry.unreadable", bundle: .module, locale: .storyArc),
            ListFormatter.localizedString(byJoining: Array(Set(offered)).sorted())
        )
    }

    @ViewBuilder
    private var artwork: some View {
        if let cover {
            cover.resizable().scaledToFill()
        } else {
            ZStack(alignment: .bottom) {
                theme.palette.surfaceRaised
                Text(entry.title)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .padding(.horizontal, StoryArcSpace.xs)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    /// Fetches the thumbnail through the same client the feed came from.
    ///
    /// Through the client, not `AsyncImage`: a private catalogue's covers are behind the
    /// same credential as its feed, and `AsyncImage` has nowhere to put one.
    private func loadCover() async {
        guard cover == nil, let url = entry.thumbnail ?? entry.cover else { return }
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
