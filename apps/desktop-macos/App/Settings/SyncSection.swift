import Persistence
import StoryArcCore
import SwiftUI

/// Sync, in the Sources tab: where the sync document lives, what the last sync did, and the
/// one menu that changes either (`library-sync`, `desktop-experience`'s *Sync when the app
/// runs*). An unreachable place is a grey sentence, never red.
struct SyncSettingsSection: View {
    let library: MacLibrary

    var body: some View {
        if let runner = library.sync.runner {
            Section {
                if let choice = runner.choice {
                    LabeledContent {
                        Text(verbatim: placeName(of: choice))
                    } label: {
                        Text("desktop.sync.place")
                    }
                    status(runner.status, place: placeName(of: choice)).foregroundStyle(.secondary)
                    Menu {
                        Button { Task { await runner.run(.chosen) } } label: { Text("desktop.sync.now") }
                            .disabled(runner.status == .syncing)
                        Divider()
                        Button { runner.turnOff() } label: { Text("desktop.sync.turnOff") }
                    } label: {
                        Text("desktop.sync.menu")
                    }
                    .fixedSize()
                } else {
                    Menu {
                        ForEach(shares) { share in
                            Button { runner.chooseShare(share.id); Task { await runner.run(.chosen) } } label: {
                                Text(verbatim: share.displayName)
                            }
                        }
                        if !shares.isEmpty { Divider() }
                        Button {
                            if MacSyncWiring.chooseFolder(for: runner) { Task { await runner.run(.chosen) } }
                        } label: {
                            Text("desktop.sync.folder")
                        }
                    } label: {
                        Text("desktop.sync.choosePlace")
                    }
                    .fixedSize()
                }
            } header: {
                Text("desktop.sync.title")
            } footer: {
                Text("desktop.sync.footer").foregroundStyle(.secondary)
            }
        }
    }

    private var shares: [Source] {
        library.servers.servers.filter { $0.kind == .networkShare }
    }

    private func placeName(of choice: SyncPlaceChoice) -> String {
        switch choice {
        case let .share(sourceID):
            library.model.registry[sourceID]?.displayName ?? String(localized: "desktop.sync.shareGone")
        case let .folder(name):
            name
        }
    }

    private func status(_ status: LibrarySyncRunner.Status, place: String) -> Text {
        switch status {
        case .off: Text("desktop.sync.status.off")
        case .idle: Text("desktop.sync.status.idle")
        case .syncing: Text("desktop.sync.status.syncing")
        case let .synced(date): Text("desktop.sync.status.synced \(date.formatted(date: .omitted, time: .shortened))")
        case .unreachable: Text("desktop.sync.status.unreachable \(place)")
        case .refused: Text("desktop.sync.status.refused")
        }
    }
}
