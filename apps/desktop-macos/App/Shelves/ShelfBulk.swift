import Foundation
import StoryArcCore
import SwiftUI

/// A bulk mark the reader can take back for ten seconds: only what the mark changed.
struct BulkMarkUndo: Identifiable, Equatable {
    let id = UUID()
    let ids: Set<String>
    let markedRead: Bool
}

/// A bulk download waiting for the reader's go-ahead, with how many it would queue.
struct BulkDownloadOffer: Identifiable, Equatable {
    let id = UUID()
    let ids: Set<String>
}

/// Bulk actions, `collections-and-reading-lists`: the single path, applied to a set.
///
/// A mark changes only the publications whose state differs (`BulkSelection.marking`), and
/// that set is what the ten-second undo puts back. A download states its count before it
/// queues anything; a catalogue entry does not give its size before it starts, so the size is
/// counted on the Downloads page as each one begins. A bulk download is not by hand, so the
/// metered rule may hold it back.
extension MacLibrary {
    /// The publications of a selection that are marked finished now.
    func finished(among ids: Set<String>) -> Set<String> {
        Set(model.publications.filter { ids.contains($0.id) && record(of: $0)?.isFinished == true }.map(\.id))
    }

    /// The publications of a selection a bulk download would fetch: catalogue rows.
    func downloadable(among ids: Set<String>) -> Set<String> {
        Set(model.publications.filter {
            ids.contains($0.id) && RemoteEntry.isDownloadable($0, in: model.registry)
        }.map(\.id))
    }

    /// Marks publications read or unread and returns those whose state changed.
    @discardableResult
    func mark(_ ids: Set<String>, read: Bool) async -> Set<String> {
        guard let progress else { return [] }
        let changing = BulkSelection.marking(ids, read: read, finished: finished(among: ids))
        for publication in model.publications where changing.contains(publication.id) {
            try? await progress.mark(publication.identity, finished: read)
        }
        await refreshProgress()
        return changing
    }

    /// Marks a selection and offers to take it back.
    func markOffering(_ ids: Set<String>, read: Bool) async {
        let changed = await mark(ids, read: read)
        guard !changed.isEmpty else { return }
        ShelfPrompts.shared.undo = BulkMarkUndo(ids: changed, markedRead: read)
    }

    func undo(_ record: BulkMarkUndo) async {
        await mark(record.ids, read: !record.markedRead)
    }

    /// Asks before a bulk download, stating how many it queues.
    func offerDownload(_ ids: Set<String>) {
        let fetching = downloadable(among: ids)
        guard !fetching.isEmpty else { return }
        ShelfPrompts.shared.downloading = BulkDownloadOffer(ids: fetching)
    }

    /// Queues every catalogue row of a selection.
    func downloadAll(_ ids: Set<String>) async {
        for publication in model.publications where ids.contains(publication.id) {
            if RemoteEntry.isDownloadable(publication, in: model.registry) {
                await download(publication, byHand: false)
            }
        }
    }
}

/// How long a bulk mark can be taken back.
enum BulkUndoWindow {
    static let duration: Duration = .seconds(10)
}

extension View {
    /// The bulk download's question and the bulk mark's ten-second undo.
    func shelfBulkPrompts(_ library: MacLibrary) -> some View {
        modifier(ShelfBulkModifier(library: library))
    }
}

private struct ShelfBulkModifier: ViewModifier {
    let library: MacLibrary

    func body(content: Content) -> some View {
        let prompts = ShelfPrompts.shared
        content
            .confirmationDialog(
                Text("desktop.bulk.download.title \(prompts.downloading?.ids.count ?? 0)"),
                isPresented: Binding(
                    get: { prompts.downloading != nil }, set: { if !$0 { prompts.downloading = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button {
                    if let offer = prompts.downloading { Task { await library.downloadAll(offer.ids) } }
                    prompts.downloading = nil
                } label: { Text("desktop.bulk.download.confirm") }
                Button(role: .cancel) { prompts.downloading = nil } label: { Text("desktop.sheet.cancel") }
            } message: {
                Text("desktop.bulk.download.body")
            }
            .overlay(alignment: .bottom) {
                if let undo = prompts.undo {
                    UndoBar(library: library, undo: undo)
                        .padding(.bottom, 20)
                        .transition(.opacity)
                }
            }
    }
}

/// The bar a bulk mark leaves for ten seconds: what changed, and *Undo*.
private struct UndoBar: View {
    let library: MacLibrary
    let undo: BulkMarkUndo

    var body: some View {
        HStack(spacing: 12) {
            if undo.markedRead {
                Text("desktop.bulk.markedRead \(undo.ids.count)")
            } else {
                Text("desktop.bulk.markedUnread \(undo.ids.count)")
            }
            Button {
                ShelfPrompts.shared.undo = nil
                Task { await library.undo(undo) }
            } label: { Text("desktop.bulk.undo") }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .task(id: undo.id) {
            try? await Task.sleep(for: BulkUndoWindow.duration)
            if ShelfPrompts.shared.undo?.id == undo.id { ShelfPrompts.shared.undo = nil }
        }
    }
}
