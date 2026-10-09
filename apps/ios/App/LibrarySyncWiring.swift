import BackgroundTasks
import Formats
import Foundation
import LibraryFeature
import Persistence
import Smb
import StoryArcCore
import SwiftUI

/// The sync runner and the moments it runs.
///
/// `library-sync` tasks 2.1 to 4.3. The foreground (4.1), leaving a publication (4.2) and the
/// background refresh iOS may grant (4.3) all call the one runner. Android's
/// `LibrarySyncWiring.kt` is the same wiring.
extension StoryArcApp {
    /// The background refresh's identifier. `project.yml` lists it under
    /// `BGTaskSchedulerPermittedIdentifiers`.
    static let syncRefreshTask = "app.storyarc.sync"

    /// The runner, over its own copies of the stores, which read and write the same files the
    /// app's do. Nil when the progress store could not be opened, which hides the Sync section,
    /// as it hides export: a sync with no progress ledger would carry no reading.
    @MainActor
    static func makeSyncRunner(progress: ProgressStore?) -> LibrarySyncRunner? {
        guard let progress else { return nil }
        let transfer = LibraryTransfer(
            archive: LibraryArchive(progress: progress, covers: CoverOverrideStore()),
            secrets: CredentialStore()
        )
        let state = LibrarySyncState()
        let places = SyncPlaceStore()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let runner = LibrarySyncRunner(
            places: places,
            placeFor: { choice in
                switch choice {
                case let .share(sourceID):
                    SourceStore().registry().sources
                        .first { $0.id == sourceID }
                        .flatMap { SmbPage(source: $0, credentials: CredentialStore()) }
                        .map { SmbSyncPlace(address: $0.address) }
                case .folder:
                    places.folder().map { FolderSyncPlace(folder: $0) }
                }
            },
            sync: { try await transfer.sync(with: $0, state: state, appVersion: version) }
        )
        // Task 5.4: the positions both devices moved reach the library's notice (D3).
        runner.onConflicts = { SyncConflicts.report($0) }
        return runner
    }

    /// After a sync wrote the stores, the settings, sources, shelves and positions the app holds
    /// in memory are read again, so a screen never saves an old copy over what the sync brought.
    func syncWroteTheStores() {
        settings = settingsStore.settings()
        Task { await library.reloadAfterImport() }
    }

    /// Task 4.1 on the way in, and task 4.3's next refresh asked for on the way out. The sync is
    /// a task of its own, so it never holds the first frame.
    func syncPhaseChanged(to phase: ScenePhase) {
        guard let syncRunner else { return }
        switch phase {
        case .active:
            Task { await syncRunner.run(.foreground) }
        case .background:
            Self.askForBackgroundRefresh(syncRunner)
        default:
            break
        }
    }

    /// Task 4.2: the reader left a publication. A Kavita publication's position goes to Kavita.
    func syncAfterLeaving(_ publication: Publication) async {
        await syncRunner?.leftPublication(ownedByKavita: kavitaProgress.origin(of: publication.id) != nil)
    }

    /// Task 4.3: what iOS runs when it grants the refresh. One sync, then the next one asked for.
    @MainActor
    static func syncInBackground(_ runner: LibrarySyncRunner?) async {
        guard let runner else { return }
        await runner.run(.background)
        askForBackgroundRefresh(runner)
    }

    @MainActor
    private static func askForBackgroundRefresh(_ runner: LibrarySyncRunner) {
        runner.scheduleBackgroundRefresh(
            submit: { moment in
                let request = BGAppRefreshTaskRequest(identifier: syncRefreshTask)
                request.earliestBeginDate = moment
                // A refused request leaves the foreground and the closing of a book, which is
                // what the setting promises. The runner logs it and Settings says so (task 5.6).
                try BGTaskScheduler.shared.submit(request)
            },
            cancel: { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: syncRefreshTask) }
        )
    }
}
