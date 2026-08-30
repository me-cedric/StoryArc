import SwiftUI

import DesignSystem
import LibraryFeature
import Persistence
import StoryArcCore

/// Everything this device can read with no network, and whatever is still on its way.
///
/// The third destination, and until this existed it was the shelf wearing a filter: the
/// tab drew `LibraryView(surface: .onDevice)`, which is the right *set* of covers and
/// nothing else — no queue, no idea what the files weigh, and no way to get rid of one.
/// The rest of it lived in Settings › Downloads and storage, three taps behind a modal,
/// which is where `offline-downloads` says it must not be: the destination "SHALL offer …
/// everything that can be read with no network — not merely the transfer queue", and
/// "a reader before a flight sees what they can read rather than what was fetched".
///
/// So this screen is a shelf first. Covers, largest surface, opening the same reader the
/// library opens. Three things sit around them:
///
/// - **The queue, and only while there is one.** `offline-downloads` is explicit that when
///   nothing is in flight "the queue is absent rather than shown empty, and the destination
///   is just the readable library". It is pinned above the shelf rather than mixed into it,
///   because a transfer is not a book yet.
/// - **What the files weigh**, once, at the foot — the question this screen is opened with
///   on a full phone, and a number that has no business competing with artwork.
/// - **Removal, undoably.** The bytes are moved aside for ten seconds rather than deleted,
///   which is the same window and the same mechanism the finish-sweep uses. Until now that
///   mechanism existed on iOS with nothing that could offer the undo.
///
/// It reads the download store itself rather than being handed the library from the app
/// layer. Two reasons: the shell can be on this tab from a cold launch with nothing else
/// having touched the store, and a destination that re-reads on appearance cannot show a
/// download that finished while the reader was somewhere else and never arrived here.
struct DownloadsDestination: View {
    @Environment(\.theme) private var theme

    let model: LibraryModel
    let onOpen: (Publication, URL) -> Void

    /// The way out of the empty state. `offline-downloads`: with nothing downloaded the
    /// destination "says so in one sentence and offers the action that changes it".
    let onShowLibrary: () -> Void

    private let store = DownloadStore()

    /// The record: what is queued, running, failed and finished.
    @State private var downloads = DownloadStore().library()

    /// What the files actually weigh, asked of the filesystem rather than summed from the
    /// record. The system can reclaim a download, and a total that counts bytes nobody has
    /// is the kind of number that makes a reader distrust the whole screen.
    @State private var bytesOnDisk: Int64 = 0

    /// The download a reader has asked to remove and not yet confirmed.
    @State private var removing: Download?

    /// A removal inside its ten-second window, still offering to come back.
    @State private var removed: RemovedDownload?

    /// Everything readable with no network at all.
    ///
    /// The same projection the shelf's on-device surface uses, and deliberately: the
    /// availability axis is *can I open this with no network*, and the answer is already on
    /// the device in the form of where each publication's bytes are. A folder the reader
    /// picked qualifies as much as a download the app fetched — a reader on a plane does
    /// not care which of the two put the file there.
    private var onDevice: [Publication] {
        model.publications.filter { model.location(of: $0)?.isFileURL == true }
    }

    /// The transfers, in the order they will be worked through.
    private var inFlight: [Download] { downloads.pending }

    private var isBare: Bool { onDevice.isEmpty && inFlight.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StoryArcSpace.xl) {
                    if !inFlight.isEmpty {
                        DownloadQueueSection(
                            downloads: inFlight,
                            onReorder: reorder,
                            onStop: { removing = $0 }
                        )
                    }

                    if isBare {
                        empty
                    } else if !onDevice.isEmpty {
                        OnDeviceShelf(
                            publications: onDevice,
                            model: model,
                            onOpen: open,
                            removable: { downloads[$0.id] != nil },
                            onRemove: { removing = downloads[$0.id] }
                        )
                        space
                    }
                }
                .padding(.vertical, StoryArcSpace.lg)
            }
            .frame(maxWidth: .infinity)
            .background(theme.palette.surfaceCanvas)
            // The same soft edge the shelf and Home use: what passes under this app's
            // chrome is artwork, and a hard cut across a cover looks like a rendering fault.
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationTitle(Text("tab.downloads"))
            .safeAreaBar(edge: .bottom) { undoBar }
        }
        // Re-read on every appearance. A download that landed while the reader was in a
        // catalogue has to be here when they arrive, not one visit later.
        .task {
            // Finished downloads are how a publication fetched from a server comes to be on
            // the shelf at all. Nothing else in the app calls this, so before this screen
            // existed a reader could download forty chapters and see none of them.
            await model.adoptDownloads()
            reload()
        }
        .alert(
            Text("downloads.remove.title"),
            isPresented: isConfirming,
            presenting: removing
        ) { download in
            Button(role: .cancel) {} label: { Text("downloads.cancel") }
            Button(role: .destructive) { remove(download) } label: { Text("downloads.remove") }
        } message: { download in
            if ImportedCopies.isImported(download) {
                // `local-library` asks for more of this sentence than a download needs.
                // Deleting an imported copy "confirms, naming the title and the space to be
                // freed, and states that the original file elsewhere is untouched" — the
                // last clause because an import is the one row here with an original
                // somewhere, and a reader must not have to guess whether the app is about
                // to reach outside itself.
                Text("downloads.remove.body.imported \(download.title) \(size(download))")
            } else {
                Text("downloads.remove.body \(download.title)")
            }
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    /// Nothing is here yet: one sentence and the one action that changes it.
    ///
    /// The destination stays present and selectable whatever the sources are doing —
    /// `navigation-shell` is explicit that a destination which disappears teaches a reader
    /// nothing — so there is no error branch, and none of this waits on a network.
    private var empty: some View {
        VStack(alignment: .leading, spacing: StoryArcSpace.lg) {
            Text("downloads.empty")
                .textRole(.callout)
                .foregroundStyle(theme.palette.textSecondary)

            Button(action: onShowLibrary) {
                Text("downloads.openLibrary")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.top, StoryArcSpace.xl)
    }

    /// What the files weigh, stated once and quietly.
    private var space: some View {
        HStack {
            Text("downloads.total")
                .foregroundStyle(theme.palette.textSecondary)
            Spacer(minLength: StoryArcSpace.md)
            Text(bytesOnDisk.formatted(.byteCount(style: .file)))
                .foregroundStyle(theme.palette.textSecondary)
        }
        .textRole(.footnote)
        .padding(.horizontal, StoryArcSpace.gutter)
    }

    /// The ten seconds in which a removal can be taken back.
    ///
    /// A bar rather than a toast, so it floats on glass above the tab bar and the shelf
    /// fades out beneath it — the same treatment the library gives its bulk actions.
    @ViewBuilder
    private var undoBar: some View {
        if let removed {
            HStack(spacing: StoryArcSpace.md) {
                Text("downloads.removed \(removed.download.title)")
                    .textRole(.footnote)
                    .foregroundStyle(theme.palette.textPrimary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                Button {
                    downloads = removed.undo(downloads, in: store)
                    self.removed = nil
                    reload()
                } label: {
                    Text("downloads.undo")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, StoryArcSpace.gutter)
            .padding(.vertical, StoryArcSpace.sm)
            .frame(maxWidth: .infinity)
            .storyArcGlass(in: RoundedRectangle(cornerRadius: StoryArcRadius.md))
            .padding(.horizontal, StoryArcSpace.gutter)
        }
    }

    private func open(_ publication: Publication) {
        if let url = model.location(of: publication) { onOpen(publication, url) }
    }

    private func size(_ download: Download) -> String {
        download.downloadedBytes.formatted(.byteCount(style: .file))
    }

    /// Moves a queued download one place. One place at a time rather than a drag, because
    /// the queue is short and a drag on a strip this size is a gesture nobody lands.
    private func reorder(_ download: Download, later: Bool) {
        downloads = downloads.moving(download.id, later: later)
        store.save(downloads)
    }

    /// Takes a download off the device, reversibly.
    ///
    /// The record goes now, so the shelf stops calling it downloaded; the bytes are moved
    /// aside and only deleted when the window closes. `offline-downloads` requires the
    /// removal to be undoable for the same window as any other, and an already-deleted file
    /// can only be put back by downloading it again — which is not an undo.
    private func remove(_ download: Download) {
        guard let outcome = store.removeAfterFinishing(download.id, from: downloads) else {
            // Nothing on disk to move aside — a record whose file the system reclaimed.
            // Forgetting it is the whole removal, and there is nothing to undo.
            downloads = store.removing(download.id, from: downloads)
            reload()
            return
        }

        downloads = outcome.library
        removed?.settle()
        removed = outcome.removed
        reload()

        let taken = outcome.removed
        Task {
            try? await Task.sleep(for: .seconds(10))
            guard removed?.download.id == taken.download.id else { return }
            taken.settle()
            removed = nil
            reload()
        }
    }

    /// Re-reads what is true after a change: the total on disk, and the shelf.
    private func reload() {
        bytesOnDisk = store.bytesOnDisk()
        // The library holds a row for every imported copy, and a row whose file has just
        // been deleted is a book that opens onto nothing.
        Task { await model.refreshImports() }
    }
}
