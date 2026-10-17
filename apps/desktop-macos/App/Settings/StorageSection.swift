import Formats
import LibraryFeature
import Persistence
import StoryArcCore
import SwiftUI

/// The real stores behind `MacStorage`.
@MainActor
enum MacStorageWiring {
    static func storage(progress: ProgressStore?, queue: DownloadQueue) -> MacStorage {
        MacStorage(
            measure: {
                MacStorage.Sizes(
                    downloads: DownloadStore().bytesOnDisk(),
                    covers: StorageUsage().cacheBytes(),
                    records: await progress?.sizeOnDisk() ?? 0
                )
            },
            freeBytes: { DownloadStore().availableBytes() },
            clear: { store in
                switch store {
                case .downloads: queue.clearing()
                case .covers:
                    CoverCache().clear()
                    await StorageUsage().clearCache()
                case .records: try? await progress?.clear()
                }
            }
        )
    }
}

/// Storage, in the Downloads tab: each store with its size and its own Clear, a grey line
/// when the disk is full, and the way to remove everything before removing the app.
///
/// `desktop-experience`, *Storage on a desktop*. Every clear is confirmed and says what goes;
/// a clear of the cache is the one offered when the disk is full.
struct StorageSection: View {
    let library: MacLibrary

    @State private var clearing: MacStorage.Store?
    @State private var isConfirmingRemoveAll = false

    var body: some View {
        let storage = library.storage
        Section {
            if storage.isFull {
                FullDiskNotice(storage: storage)
            }
            ForEach(MacStorage.Store.allCases, id: \.self) { store in
                LabeledContent {
                    HStack {
                        Text(verbatim: DownloadStore.formatted(storage.sizes[store])).foregroundStyle(.secondary)
                        Button { clearing = store } label: { Text("desktop.storage.clear") }
                            .accessibilityLabel(Text("desktop.storage.clear.label \(Text(store.titleKey))"))
                            .disabled(storage.sizes[store] == 0)
                    }
                } label: {
                    Text(store.titleKey)
                }
            }
        } header: {
            Text("desktop.storage.title")
        } footer: {
            Text("desktop.storage.footer").foregroundStyle(.secondary)
        }
        .task { await storage.refresh() }
        .confirmationDialog(
            Text(clearing?.confirmKey ?? "desktop.storage.clear"),
            isPresented: Binding(get: { clearing != nil }, set: { if !$0 { clearing = nil } }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                if let clearing { Task { await clear(clearing) } }
                clearing = nil
            } label: { Text("desktop.storage.clear") }
        } message: {
            Text(clearing?.bodyKey ?? "")
        }
        Section {
            Button(role: .destructive) { isConfirmingRemoveAll = true } label: { Text("desktop.storage.removeAll") }
                .confirmationDialog(Text("desktop.storage.removeAll.title"), isPresented: $isConfirmingRemoveAll) {
                    Button(role: .destructive) { Task { await library.removeAllData() } } label: {
                        Text("desktop.storage.removeAll.confirm")
                    }
                } message: {
                    Text("desktop.storage.removeAll.body")
                }
        } footer: {
            Text("desktop.storage.removeAll.footer").foregroundStyle(.secondary)
        }
    }

    private func clear(_ store: MacStorage.Store) async {
        await library.storage.clear(store)
        if store == .records { await library.refreshProgress() }
    }
}

/// The grey line a full disk earns, with the one clear that costs nothing to lose.
struct FullDiskNotice: View {
    let storage: MacStorage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("desktop.storage.full", systemImage: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.secondary)
            Button { Task { await storage.clear(.covers) } } label: { Text("desktop.storage.full.clear") }
        }
    }
}

extension MacStorage.Store {
    var titleKey: LocalizedStringKey {
        switch self {
        case .downloads: "desktop.storage.downloads"
        case .covers: "desktop.storage.covers"
        case .records: "desktop.storage.records"
        }
    }

    var confirmKey: LocalizedStringKey {
        switch self {
        case .downloads: "desktop.storage.downloads.confirm"
        case .covers: "desktop.storage.covers.confirm"
        case .records: "desktop.storage.records.confirm"
        }
    }

    var bodyKey: LocalizedStringKey {
        switch self {
        case .downloads: "desktop.storage.downloads.body"
        case .covers: "desktop.storage.covers.body"
        case .records: "desktop.storage.records.body"
        }
    }
}
