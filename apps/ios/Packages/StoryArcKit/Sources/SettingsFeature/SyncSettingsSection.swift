internal import SwiftUI
internal import UniformTypeIdentifiers

internal import DesignSystem
internal import Persistence
internal import StoryArcCore

/// Where the sync document lives, and what the sync is doing.
///
/// `library-sync` tasks 2.1, 2.4 and 4.4. Sync is off until the reader chooses a place: a share
/// they already added, or a folder through the system picker. The section states that every
/// device must reach the same place, and what this platform does and when. The status line is
/// grey text, never red: an unreachable place is a normal state. Android's `SyncRows` is the
/// same section.
struct SyncSettingsSection: View {
    @Environment(\.theme) private var theme

    let runner: LibrarySyncRunner
    /// Every source, so a chosen share is named and the shares can be offered.
    let sources: [Source]
    var highlight: SettingsAnchor?

    @State private var isPickingFolder = false
    @State private var isFolderRefused = false

    private var shares: [Source] { sources.filter { $0.kind == .networkShare } }

    var body: some View {
        Section {
            if let choice = runner.choice {
                LabeledContent {
                    Text(Self.placeName(of: choice, in: sources))
                } label: {
                    Text("sync.place", bundle: .module)
                }
                .settingsHighlight(.sync, when: highlight)
                if let line = Self.statusLine(runner.status, place: Self.placeName(of: choice, in: sources)) {
                    Text(line, bundle: .module)
                        .textRole(.footnote)
                        .foregroundStyle(theme.palette.textSecondary)
                }
                Button { Task { await runner.run(.chosen) } } label: {
                    Text("sync.now", bundle: .module)
                }
                .disabled(runner.status == .syncing)
                Button { runner.turnOff() } label: {
                    Text("sync.turnOff", bundle: .module)
                }
            } else {
                if !shares.isEmpty {
                    Menu {
                        ForEach(shares) { share in
                            Button(share.displayName) { chose { runner.chooseShare(share.id) } }
                        }
                    } label: {
                        Label { Text("sync.chooseShare", bundle: .module) } icon: { Image(systemName: "server.rack") }
                    }
                }
                Button { isPickingFolder = true } label: {
                    Label { Text("sync.chooseFolder", bundle: .module) } icon: { Image(systemName: "folder") }
                }
                .settingsHighlight(.sync, when: highlight)
            }
        } header: {
            Text("sync.title", bundle: .module)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if runner.choice == nil { Text("sync.about", bundle: .module) }
                Text("sync.everyDevice", bundle: .module)
                Text("sync.when", bundle: .module)
            }
        }
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder], onCompletion: picked)
        .alert(Text("sync.folderRefused", bundle: .module), isPresented: $isFolderRefused) {}
    }

    private func picked(_ result: Result<URL, any Error>) {
        guard case let .success(url) = result else { return }
        // The picker's grant lasts while the scope is open; the bookmark is made inside it.
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try runner.chooseFolder(url)
            Task { await runner.run(.chosen) }
        } catch {
            isFolderRefused = true
        }
    }

    private func chose(_ choose: () -> Void) {
        choose()
        Task { await runner.run(.chosen) }
    }

    /// What the chosen place is called: the share's name, or the folder's.
    static func placeName(of choice: SyncPlaceChoice, in sources: [Source]) -> String {
        switch choice {
        case let .share(sourceID): sources.first { $0.id == sourceID }?.displayName ?? ""
        case let .folder(name): name
        }
    }

    /// The status line, or nil when there is nothing to say. Lifted out of the view so a test
    /// reads which sentence each state draws.
    static func statusLine(_ status: LibrarySyncRunner.Status, place: String) -> LocalizedStringKey? {
        switch status {
        case .off: nil
        case .idle: "sync.status.idle"
        case .syncing: "sync.status.syncing"
        case let .synced(moment):
            "sync.status.synced \(Self.time(of: moment))"
        case .unreachable: "sync.status.unreachable \(place)"
        case .refused(.newerThanThisApp): "sync.status.newer"
        case .refused: "sync.status.notLibrary"
        }
    }

    /// The time of today's sync, or the date and time of an older one, in the app's language.
    private static func time(of moment: Date) -> String {
        let date: Date.FormatStyle.DateStyle = Calendar.current.isDateInToday(moment) ? .omitted : .abbreviated
        return moment.formatted(Date.FormatStyle(date: date, time: .shortened).locale(.storyArc))
    }
}
