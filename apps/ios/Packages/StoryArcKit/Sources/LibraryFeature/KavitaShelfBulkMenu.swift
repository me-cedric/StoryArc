internal import SwiftUI

internal import DesignSystem
internal import Kavita
internal import Persistence

/// Download and mark read, for everything a server's collection or reading list holds.
///
/// Task 7.8 of `close-the-audited-gaps`. The same two actions the local shelves have, over a
/// server's chapters: the download states the count and the size and waits for a yes, and the
/// mark is undoable for ten seconds. Android's `KavitaShelfBulkMenu` is its twin.
///
/// A modifier rather than a copy in each of the two screens, because a collection and a list
/// differ in how they are shown and not at all in what can be done to everything inside them.
struct KavitaShelfBulkActions: ViewModifier {
    let server: KavitaPage

    /// The chapters the shelf holds, or nil when the server could not say.
    let load: @Sendable () async -> [KavitaShelfChapter]?

    /// Called when marks were sent or taken back, so the screen can ask the server for the
    /// state it now holds.
    let onMarked: () async -> Void

    @State private var isWorking = false
    @State private var pending: KavitaBulkDownloadAsk?
    @State private var isAllOnDevice = false
    @State private var isUnreachable = false
    @State private var undo: KavitaMarkUndo?

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if let undo {
                    KavitaMarkUndoBar(
                        record: undo,
                        onUndo: { await send(undo.chapters, read: !undo.read) },
                        onSettle: { self.undo = nil }
                    )
                    .storyArcGlass(in: Capsule())
                    .padding(.horizontal, StoryArcSpace.gutter)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if isWorking { ProgressView() } else { menu }
                }
            }
            .alert(
                Text("library.bulk.download.none", bundle: .module),
                isPresented: $isAllOnDevice
            ) {
                Button(role: .cancel) {} label: { Text("shelves.cancel", bundle: .module) }
            }
            .alert(
                Text("kavita.bulk.unreachable \(server.title)", bundle: .module),
                isPresented: $isUnreachable
            ) {
                Button(role: .cancel) {} label: { Text("library.import.dismiss", bundle: .module) }
            }
            .confirmationDialog(
                Text("library.bulk.download.title \(pending?.count ?? 0)", bundle: .module),
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                titleVisibility: .visible
            ) {
                Button {
                    if let ask = pending { start(ask) }
                } label: {
                    Text("library.bulk.download", bundle: .module)
                }
                Button(role: .cancel) {} label: { Text("shelves.cancel", bundle: .module) }
            } message: {
                Text(sizeSentence(pending?.size ?? .unstated))
            }
    }

    private var menu: some View {
        Menu {
            Button {
                Task { await markAll() }
            } label: {
                Label {
                    Text("library.mark.read", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
            }
            Button {
                Task { await askToDownload() }
            } label: {
                Label {
                    Text("library.bulk.download", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.down.circle")
                }
            }
        } label: {
            Label {
                Text("shelves.bulk", bundle: .module)
            } icon: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    /// The one sentence that states what a download will copy, in whichever way the server
    /// left it.
    private func sizeSentence(_ size: KavitaBulkSize) -> String {
        switch size {
        case let .known(bytes):
            String(
                format: String(localized: "library.bulk.download.size %@", bundle: .module, locale: .storyArc),
                DownloadStore.formatted(bytes)
            )
        case let .atLeast(bytes):
            String(
                format: String(localized: "kavita.bulk.size.atLeast %@", bundle: .module, locale: .storyArc),
                DownloadStore.formatted(bytes)
            )
        case .unstated:
            String(localized: "kavita.bulk.size.unknown", bundle: .module, locale: .storyArc)
        }
    }

    private func askToDownload() async {
        isWorking = true
        defer { isWorking = false }
        guard let held = await load() else { return isUnreachable = true }
        let kept = Set(KavitaCardStore().all(from: server.id).map(\.chapterId))
        if let ask = KavitaShelfBulk.downloadAsk(held, kept: kept) { pending = ask } else { isAllOnDevice = true }
    }

    /// Queues what the reader was told about. Unstructured, so leaving the screen does not drop
    /// the steps that index each file and file its card when the transfer lands.
    private func start(_ ask: KavitaBulkDownloadAsk) {
        let client = KavitaClient(address: server.address)
        let (sourceID, source) = (server.id, UUID(uuidString: server.id))
        Task {
            _ = await KavitaShelfBulk.download(ask) { each in
                await KavitaKeep.keep(
                    KavitaKeep.Subject(
                        chapter: each.chapter,
                        series: each.series,
                        metadata: nil,
                        origin: each.origin(sourceID: sourceID),
                        sourceID: source
                    ),
                    client: client,
                    progress: KavitaProgressStore()
                ) != nil
            }
        }
    }

    private func markAll() async {
        isWorking = true
        defer { isWorking = false }
        guard let held = await load() else { return isUnreachable = true }
        let moving = KavitaShelfBulk.changing(held, read: true)
        guard !moving.isEmpty else { return }
        await send(moving, read: true)
        undo = KavitaMarkUndo(chapters: moving, read: true)
    }

    /// Marks each chapter for this server, which holds the mark if it is not there.
    private func send(_ chapters: [KavitaShelfChapter], read: Bool) async {
        let store = KavitaProgressStore()
        let (sourceID, address) = (server.id, server.address)
        await KavitaShelfBulk.mark(chapters, read: read) { each, isRead in
            await KavitaSync.mark(isRead, for: each.origin(sourceID: sourceID), to: address, in: store)
        }
        await onMarked()
    }
}

/// The offer to take a whole-shelf mark back, which closes ten seconds after it opened.
private struct KavitaMarkUndoBar: View {
    let record: KavitaMarkUndo
    let onUndo: () async -> Void
    /// Called when the offer is taken or its window closes. Either way it is over.
    let onSettle: () -> Void

    var body: some View {
        HStack(spacing: StoryArcSpace.md) {
            Text("library.bulk.changed \(record.chapters.count)", bundle: .module)
                .textRole(.footnote)
                .storyArcGlassText()
            Button {
                Task {
                    await onUndo()
                    onSettle()
                }
            } label: {
                Text("library.bulk.undo", bundle: .module)
                    .textRole(.footnote)
            }
        }
        .padding(.horizontal, StoryArcSpace.gutter)
        .padding(.vertical, StoryArcSpace.sm)
        .task(id: record.id) {
            try? await Task.sleep(for: .seconds(KavitaShelfBulk.undoSeconds))
            guard !Task.isCancelled else { return }
            onSettle()
        }
    }
}

extension View {
    /// Download and mark read, for everything a server's collection or reading list holds.
    func kavitaShelfBulkActions(
        server: KavitaPage,
        load: @escaping @Sendable () async -> [KavitaShelfChapter]?,
        onMarked: @escaping () async -> Void = {}
    ) -> some View {
        modifier(KavitaShelfBulkActions(server: server, load: load, onMarked: onMarked))
    }
}
