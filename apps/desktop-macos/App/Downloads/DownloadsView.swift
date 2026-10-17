import AppKit
import DesignSystem
import LibraryFeature
import Persistence
import StoryArcCore
import SwiftUI

/// The Downloads destination: what is on its way, then what is on this Mac.
///
/// `offline-downloads`: one view of the queue with each item's size and progress, per-item
/// and global pause, resume and cancel. `desktop-experience`, *Metered connections*: a row
/// the rule holds says why in grey and offers *Download Now*. A row's actions are one menu,
/// the destructive one last (`AGENTS.md` section 6). Nothing here posts a notification.
struct DownloadsView: View {
    @Environment(\.theme) private var theme
    let downloads: MacDownloads
    let onRead: (URL) -> Void

    @State private var removing: Download?

    var body: some View {
        Group {
            if downloads.downloads.isEmpty {
                ContentUnavailableView {
                    Label("desktop.downloads.empty.title", systemImage: "arrow.down.circle")
                } description: {
                    Text("desktop.downloads.empty.body")
                }
            } else {
                // A grouped form rather than a list: a list row draws its menu button at the
                // mini size, 12 points tall, under the floor the audit holds (measured).
                Form {
                    if !downloads.pending.isEmpty { queueSection }
                    if !downloads.finished.isEmpty { finishedSection }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.surfaceCanvas)
        .confirmationDialog(
            Text("desktop.downloads.remove.title \(removing?.title ?? "")"),
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let removing { downloads.remove(removing.id) }
                removing = nil
            } label: { Text("desktop.downloads.remove.confirm") }
        } message: {
            Text("desktop.downloads.remove.body")
        }
    }

    private var queueSection: some View {
        Section {
            ForEach(downloads.pending) { download in
                DownloadRow(download: download, status: status(of: download)) {
                    rowMenu(download)
                }
            }
        } header: {
            HStack {
                Text("desktop.downloads.queue")
                Spacer()
                Menu {
                    Button { downloads.queue.pauseAll() } label: { Text("desktop.downloads.pauseAll") }
                    Button { downloads.queue.resumeAll() } label: { Text("desktop.downloads.resumeAll") }
                } label: {
                    Label("desktop.downloads.queueActions", systemImage: "ellipsis").labelStyle(.iconOnly)
                }
                .rowMenu()
            }
        }
    }

    private var finishedSection: some View {
        Section {
            ForEach(downloads.finished) { download in
                DownloadRow(download: download, status: Text(DownloadStore.formatted(download.downloadedBytes))) {
                    if let file = downloads.queue.file(of: download.id) {
                        Button { onRead(file) } label: { Text("desktop.menu.read") }
                        Button { NSWorkspace.shared.activateFileViewerSelecting([file]) } label: {
                            Text("desktop.menu.showInFinder")
                        }
                        Divider()
                    }
                    Button(role: .destructive) { removing = download } label: { Text("desktop.downloads.remove") }
                }
            }
        } header: {
            Text("desktop.downloads.onMac")
        }
    }

    @ViewBuilder
    private func rowMenu(_ download: Download) -> some View {
        if downloads.held.contains(download.id) {
            Button { downloads.startByHand(download.id) } label: { Text("desktop.downloads.now") }
        }
        switch download.state {
        case .queued, .running:
            if !downloads.held.contains(download.id) {
                Button { downloads.pause(download.id) } label: { Text("desktop.downloads.pause") }
            }
        case .paused, .failed:
            if !downloads.held.contains(download.id) {
                Button { downloads.resume(download.id) } label: { Text("desktop.downloads.resume") }
            }
        case .finished:
            EmptyView()
        }
        Divider()
        Button(role: .destructive) { downloads.cancel(download.id) } label: { Text("desktop.downloads.cancel") }
    }

    /// The grey line under a row: why it waits, or how far it got.
    private func status(of download: Download) -> Text {
        switch downloads.reason(for: download) {
        case .metered: return Text("desktop.downloads.waiting.metered")
        case .offline: return Text("desktop.downloads.waiting.offline")
        case nil: break
        }
        switch download.state {
        case .queued: return Text("desktop.downloads.queued")
        case .paused(.outOfSpace): return Text("desktop.downloads.paused.space")
        case .paused: return Text("desktop.downloads.paused")
        case .failed: return Text("desktop.downloads.failed")
        case .running, .finished:
            let done = DownloadStore.formatted(download.downloadedBytes)
            guard let expected = download.expectedBytes else {
                return Text("desktop.downloads.progress.unknown \(done)")
            }
            return Text("desktop.downloads.progress \(done) \(DownloadStore.formatted(expected))")
        }
    }
}

extension View {
    /// A row's one menu of actions, as the system's pull-down button.
    ///
    /// The automatic style rather than a borderless or button style: those draw an icon-only
    /// menu 12 to 15 points tall, under the 20-point floor the audit holds a control to
    /// (measured 2026-10-17), and padding a hit region around a smaller glyph is a fault of
    /// its own (`AGENTS.md` section 6).
    func rowMenu() -> some View {
        menuStyle(.automatic)
            .fixedSize()
    }
}

/// One download: its title, its progress, the grey line, and its menu.
struct DownloadRow<Actions: View>: View {
    let download: Download
    let status: Text
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: download.state.isFinished ? "checkmark.circle" : "arrow.down.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(download.title).lineLimit(2)
                if download.state == .running {
                    ProgressView(value: download.fraction ?? 0)
                        .accessibilityLabel(Text("desktop.downloads.progressLabel \(download.title)"))
                }
                status.scaledFont(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                actions()
            } label: {
                Label("desktop.downloads.actions \(download.title)", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .rowMenu()
        }
        .padding(.vertical, 4)
    }
}
