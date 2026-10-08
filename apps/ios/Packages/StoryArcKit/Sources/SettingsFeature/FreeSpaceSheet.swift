internal import SwiftUI

internal import DesignSystem
internal import Persistence
internal import StoryArcCore

/// The remedy the storage hold names but used not to offer: finished publications, largest
/// first, each removable without leaving Settings.
///
/// `offline-downloads`' *Storage limit* says the app "pauses downloads" and the hold "states
/// a remedy"; until now that remedy was a sentence pointing at a screen with no action of its
/// own. This sheet is that action, with the same ten-second undo every other removal offers.
///
/// Reads a snapshot rather than the live queue — `SettingsFeature` holds no queue of its own,
/// by the same rule ``DownloadsSettings`` already follows — and keeps its own copy in
/// ``downloads`` so a removal updates the list without a second round trip to the caller.
struct FreeSpaceSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var downloads: DownloadLibrary

    /// Takes the download off the device, reversibly. `nil` when there was nothing to take.
    let onRemove: (Download) -> RemovedDownload?

    /// Puts a removed download back, undoing ``onRemove``.
    let onRestore: (RemovedDownload) -> Void

    @State private var removed: RemovedDownload?

    init(
        downloads: DownloadLibrary,
        onRemove: @escaping (Download) -> RemovedDownload?,
        onRestore: @escaping (RemovedDownload) -> Void
    ) {
        _downloads = State(initialValue: downloads)
        self.onRemove = onRemove
        self.onRestore = onRestore
    }

    var body: some View {
        NavigationStack {
            List(downloads.largestFirst) { download in
                HStack {
                    VStack(alignment: .leading) {
                        Text(download.title)
                        Text(DownloadStore.formatted(download.downloadedBytes))
                            .textRole(.footnote)
                            .foregroundStyle(theme.palette.textSecondary)
                    }
                    Spacer(minLength: StoryArcSpace.md)
                    Button(role: .destructive) { remove(download) } label: {
                        Image(systemName: "trash").hitRegion()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.palette.textSecondary)
                    .accessibilityLabel(Text("downloads.remove.action \(download.title)", bundle: .module))
                }
            }
            .navigationTitle(Text("downloads.held.freeSpace", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("settings.done", bundle: .module) }
                }
            }
            .safeAreaBar(edge: .bottom) { undoBar }
        }
    }

    @ViewBuilder
    private var undoBar: some View {
        if let removed {
            HStack(spacing: StoryArcSpace.md) {
                Text("downloads.removed \(removed.download.title)", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                Button { restore(removed) } label: { Text("downloads.undo", bundle: .module) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.vertical, StoryArcSpace.sm)
        }
    }

    private func remove(_ download: Download) {
        guard let taken = onRemove(download) else { return }
        downloads = downloads.removing(download.id)
        removed?.settle()
        removed = taken

        Task {
            try? await Task.sleep(for: .seconds(10))
            guard removed?.download.id == taken.download.id else { return }
            taken.settle()
            removed = nil
        }
    }

    private func restore(_ taken: RemovedDownload) {
        onRestore(taken)
        downloads = downloads.queueing(taken.download)
        removed = nil
    }
}
