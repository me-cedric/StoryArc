import SwiftUI

import DesignSystem
import LibraryFeature
import Persistence
import StoryArcCore

/// What the files weigh, broken down.
///
/// `offline-downloads` asks the storage view to state the total "broken down by source",
/// to offer "a largest-first list, each removable", and to state "the cover cache size"
/// beside the downloads total. Until now this row said only the one number.
///
/// Split out of ``DownloadsDestination``, which is at the 400-line cap this project
/// enforces, and parameterised the way ``DownloadQueueSection`` and ``OnDeviceShelf`` are —
/// a feature module never depends on the app target, so the facts it needs come in rather
/// than being read from a model it cannot import.
struct StorageBreakdownSection: View {
    @Environment(\.theme) private var theme

    /// What the app's own downloads directory weighs, asked of the filesystem by the caller
    /// for the reason it always is: the system can reclaim a download, and a total counting
    /// bytes nobody has is the kind of number that makes a reader distrust the screen.
    let totalBytes: Int64

    /// What the cover cache alone is holding — distinct from the total above, which it is
    /// not part of.
    let coverCacheBytes: Int64

    /// What is on the device and what is still on its way, for the per-source and
    /// largest-first breakdowns below.
    let downloads: DownloadLibrary

    /// Where each download's source is named.
    let registry: SourceRegistry

    /// Removes one finished download, through the same confirmation the on-device shelf's
    /// own remove action raises.
    let onRemove: (Download) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            statRow(Text("downloads.total"), totalBytes)
            ForEach(bySource) { entry in
                statRow(Text(verbatim: entry.name), entry.bytes)
            }
            statRow(Text("downloads.cache"), coverCacheBytes)

            if !largest.isEmpty {
                Text("downloads.largest")
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                    .padding(.top, StoryArcSpace.sm)

                ForEach(largest) { download in
                    HStack(spacing: StoryArcSpace.sm) {
                        Text(download.title)
                            .lineLimit(1)
                            .foregroundStyle(theme.palette.textPrimary)
                        Spacer(minLength: StoryArcSpace.md)
                        Text(DownloadStore.formatted(download.downloadedBytes))
                            .foregroundStyle(theme.palette.textSecondary)
                        Button(role: .destructive) { onRemove(download) } label: {
                            Image(systemName: "trash").hitRegion()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("downloads.remove.action \(download.title)"))
                    }
                    .textRole(.footnote)
                }
            }
        }
        .textRole(.footnote)
        .padding(.horizontal, StoryArcSpace.gutter)
    }

    private func statRow(_ title: Text, _ bytes: Int64) -> some View {
        HStack {
            title.foregroundStyle(theme.palette.textSecondary)
            Spacer(minLength: StoryArcSpace.md)
            Text(DownloadStore.formatted(bytes))
                .foregroundStyle(theme.palette.textSecondary)
        }
    }

    /// The total broken down by source, named and ordered largest first.
    ///
    /// A download with no source of its own, or one whose source has since been removed,
    /// is left out rather than named "nil" — the total above already counts it. Keyed by the
    /// source's id, because two sources can carry the same name.
    private var bySource: [SourceTotal] {
        downloads.bytesBySource
            .compactMap { sourceID, bytes -> SourceTotal? in
                guard let sourceID, let source = registry[sourceID] else { return nil }
                return SourceTotal(id: sourceID, name: source.displayName, bytes: bytes)
            }
            .sorted { $0.bytes > $1.bytes }
    }

    /// What can be deleted, largest first — "what can I delete" is the question the total
    /// states to answer, and the finished downloads are the only rows this screen can
    /// remove at all.
    private var largest: [Download] {
        Array(downloads.largestFirst.prefix(Self.largestCount))
    }

    private static let largestCount = 10

    /// One source's share of the total.
    private struct SourceTotal: Identifiable {
        let id: UUID
        let name: String
        let bytes: Int64
    }
}
