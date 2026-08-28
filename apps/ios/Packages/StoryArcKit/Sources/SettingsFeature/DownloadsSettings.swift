internal import SwiftUI

internal import DesignSystem
internal import StoryArcCore

/// What is on the device, what it weighs, and how to get rid of it.
///
/// `offline-downloads` asks for a storage view showing "total space used ... broken down by
/// source and by the largest publications", where "each row can be removed individually".
/// This is the first cut of that: the total, the rows, and removal.
///
/// Handed its data rather than owning it, for the same reason ``SourcesSettings`` is: a
/// feature module never depends on another feature module, and the downloads belong to the
/// library that fetched them.
struct DownloadsSettings: View {
    @Environment(\.theme) private var theme

    let library: DownloadLibrary

    /// What the files actually weigh. Asked of the filesystem by the caller, because the
    /// system can reclaim a download and a total that counts bytes nobody has is the kind
    /// of number that makes a reader distrust the whole screen.
    let bytesOnDisk: Int64

    /// The reader's own policy for the queue, and how to change it.
    @Binding var settings: AppSettings

    /// The name of the source a download came from, when it came from one.
    let sourceName: (UUID) -> String?

    let onRemove: (Download) -> Void

    /// Moves a queued download one place. `offline-downloads` asks for reorder among the
    /// queue's own controls, and one place at a time is reachable without a drag gesture.
    var onReorder: (Download, Bool) -> Void = { _, _ in }

    @State private var removing: Download?

    private var isRemoving: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    /// Largest first, which is the order the question "what can I delete" is asked in.
    private var finished: [Download] {
        library.finished.sorted { $0.downloadedBytes > $1.downloadedBytes }
    }

    var body: some View {
        List {
            policy

            if finished.isEmpty && library.pending.isEmpty {
                Text("downloads.none", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            } else {
                Section {
                    LabeledContent {
                        Text(bytesOnDisk.formatted(.byteCount(style: .file)))
                            .foregroundStyle(theme.palette.textSecondary)
                    } label: {
                        Text("downloads.total", bundle: .module)
                            .foregroundStyle(theme.palette.textPrimary)
                    }
                }

                if !library.pending.isEmpty {
                    Section {
                        ForEach(library.pending) { download in
                            pending(download)
                        }
                    } header: {
                        Text("downloads.pending", bundle: .module)
                    }
                }

                if !finished.isEmpty {
                    Section {
                        ForEach(finished) { download in
                            row(download)
                        }
                    } header: {
                        Text("downloads.onDevice", bundle: .module)
                    }
                }
            }
        }
        // Confirmed, because it deletes bytes. `offline-downloads` says the app "never
        // deletes a download without asking", and although that sentence is about the
        // low-storage case, a reader's own tap deserves the same courtesy.
        .alert(
            Text("downloads.remove.title", bundle: .module),
            isPresented: isRemoving,
            presenting: removing
        ) { download in
            Button(role: .cancel) {} label: { Text("downloads.cancel", bundle: .module) }
            Button(role: .destructive) {
                onRemove(download)
            } label: {
                Text("downloads.remove", bundle: .module)
            }
        } message: { download in
            Text("downloads.remove.body \(download.title)", bundle: .module)
        }
        .navigationTitle(Text("settings.downloads", bundle: .module))
    }

    @ViewBuilder
    private func row(_ download: Download) -> some View {
        HStack(spacing: StoryArcSpace.md) {
            VStack(alignment: .leading, spacing: StoryArcSpace.hair) {
                Text(download.title)
                    .foregroundStyle(theme.palette.textPrimary)

                Text(subtitle(download))
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            }

            Spacer(minLength: 0)

            Button(role: .destructive) {
                removing = download
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("downloads.remove.action \(download.title)", bundle: .module))
        }
    }

    /// Size, and which source it came from when it came from one.
    private func subtitle(_ download: Download) -> String {
        let size = download.downloadedBytes.formatted(.byteCount(style: .file))
        guard let sourceID = download.sourceID, let name = sourceName(sourceID) else {
            return size
        }
        return "\(name) · \(size)"
    }

    @ViewBuilder
    private func pending(_ download: Download) -> some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.xs) {
            HStack {
                Text(download.title)
                    .foregroundStyle(theme.palette.textPrimary)
                Spacer(minLength: 0)
                // Only a queued download has an order to change: a running one has started
                // and the list is short enough that its ends are obvious.
                if download.state == .queued {
                    Button { onReorder(download, false) } label: {
                        Label {
                            Text("downloads.moveEarlier \(download.title)", bundle: .module)
                        } icon: {
                            Image(systemName: "chevron.up")
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)

                    Button { onReorder(download, true) } label: {
                        Label {
                            Text("downloads.moveLater \(download.title)", bundle: .module)
                        } icon: {
                            Image(systemName: "chevron.down")
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                }
            }

            switch download.state {
            case let .failed(reason, attempts):
                // The reason, in the reader's words, and how many times it was tried.
                // `offline-downloads` requires "a plain-language reason and a retry action";
                // the retry is not built yet, which is why the count is shown rather than
                // hidden behind a button that does not exist.
                Text("downloads.failed \(reason) \(attempts)", bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(StoryArcColor.Status.danger)
            case let .paused(pause):
                Text(pause.explanationKey, bundle: .module)
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textSecondary)
            case .queued, .running, .finished:
                if let fraction = download.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }
        }
    }
}

extension Download.Pause {
    /// Why this one is not moving, in the reader's terms.
    var explanationKey: LocalizedStringKey {
        switch self {
        case .byReader: "downloads.paused.byReader"
        case .waitingForWiFi: "downloads.paused.waitingForWiFi"
        case .outOfSpace: "downloads.paused.outOfSpace"
        }
    }
}

extension DownloadsSettings {
    /// What the reader has asked of the queue.
    ///
    /// The three `offline-downloads` calls policy: whether to wait for Wi-Fi, how much disk
    /// to spend, and whether a finished publication keeps its download. All three change
    /// what the queue does rather than how it looks, which is why they sit above the list of
    /// files rather than inside it.
    @ViewBuilder
    fileprivate var policy: some View {
        Section {
            Toggle(isOn: $settings.downloadOverWifiOnly) {
                VStack(alignment: .leading) {
                    Text("downloads.wifiOnly", bundle: .module)
                    Text("downloads.wifiOnly.note", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textTertiary)
                }
            }

            Toggle(isOn: $settings.removeDownloadsAfterFinishing) {
                VStack(alignment: .leading) {
                    Text("downloads.removeAfter", bundle: .module)
                    Text("downloads.removeAfter.note", bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textTertiary)
                }
            }

            // A short ladder rather than a free number: a reader knows "about five
            // gigabytes", not 5_000_000_000, and a field for a byte count is a way to
            // mistype one. Round decimal values, because that is how a size is shown.
            Picker(selection: $settings.maximumDownloadBytes) {
                Text("downloads.limit.none", bundle: .module).tag(Int64?.none)
                ForEach(Self.limits, id: \.self) { limit in
                    Text(limit.formatted(.byteCount(style: .file))).tag(Int64?.some(limit))
                }
            } label: {
                Text("downloads.limit", bundle: .module)
            }
        }
    }

    fileprivate static let limits: [Int64] = [1_000_000_000, 5_000_000_000, 20_000_000_000]
}
