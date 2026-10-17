import AppKit
import Formats
import LibraryFeature
import Persistence
import Smb
import StoryArcCore

/// The sync runner over this Mac's stores, and where its folder is kept.
///
/// A Mac copy of `apps/ios/App/LibrarySyncWiring.swift`'s `makeSyncRunner`, with one change
/// the sandbox forces: a folder is kept as a security-scoped bookmark in `MacFolderBookmarks`
/// under its own key, because the package's store mints the minimal bookmark a sandboxed
/// Mac cannot open on the next launch (`design.md` Decision 8). A share needs no bookmark.
@MainActor
enum MacSyncWiring {
    static let folderKey = "app.storyarc.mac.syncFolder"

    static var folderBookmarks: MacFolderBookmarks { MacFolderBookmarks(key: folderKey) }

    static func runner(progress: ProgressStore?) -> LibrarySyncRunner? {
        guard let progress else { return nil }
        let transfer = LibraryTransfer(
            archive: LibraryArchive(progress: progress, covers: CoverOverrideStore()),
            secrets: CredentialStore()
        )
        let state = LibrarySyncState()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return LibrarySyncRunner(
            places: SyncPlaceStore(),
            placeFor: { choice in
                switch choice {
                case let .share(sourceID):
                    SourceStore().registry().sources
                        .first { $0.id == sourceID }
                        .flatMap { SmbPage(source: $0, credentials: CredentialStore()) }
                        .map { SmbSyncPlace(address: $0.address) }
                case .folder:
                    folder().map { FolderSyncPlace(folder: $0) }
                }
            },
            sync: { try await transfer.sync(with: $0, state: state, appVersion: version) }
        )
    }

    /// The system's folder chooser, then the folder kept for the next launch and chosen.
    static func chooseFolder(for runner: LibrarySyncRunner) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "desktop.sync.choose")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try runner.chooseFolder(url)
        } catch {
            return false
        }
        folderBookmarks.removeAll()
        try? folderBookmarks.add(url)
        resolved?.end()
        resolved = nil
        return true
    }

    /// The chosen folder, opened from its bookmark once a launch; its access stays open while
    /// the app runs, as the library's folders' does.
    private static var resolved: FolderAccess?

    static func folder() -> URL? {
        if let resolved { return resolved.url }
        resolved = folderBookmarks.restore().folders.first
        return resolved?.url
    }

    /// When a reading position last changed, for the quit's question.
    static func latestChange(in progress: ProgressStore?) async -> Date? {
        guard let progress else { return nil }
        return (try? await progress.recent(limit: 1))?.first?.updatedAt
    }
}
