import Persistence
@testable import SettingsFeature
import StoryArcCore
import SwiftUI
import Synchronization
import XCTest

/// A secret store with nothing in it, so a sync can run without the keychain.
private final class NoSecrets: SourceSecretStore {
    func save(_ secret: String, for reference: String) -> Bool { true }
    func secret(for reference: String) -> String? { nil }
    func remove(_ reference: String) -> Bool { true }
}

/// A sync place held in memory, so the section can show a sync that ran.
private final class MemoryPlace: SyncPlace {
    private let files = Mutex<[String: SyncFile]>([:])
    private let writes = Mutex(0)

    func names() async throws -> [String] { files.withLock { Array($0.keys) } }
    func read(_ name: String) async throws -> SyncFile? { files.withLock { $0[name] } }
    func write(_ name: String, data: Data, replacing: String?) async throws -> Bool {
        files.withLock { held in
            guard held[name]?.version == replacing else { return false }
            let version = writes.withLock { $0 += 1; return "v\($0)" }
            held[name] = SyncFile(data: data, version: version)
            return true
        }
    }
    func delete(_ name: String) async throws -> Bool { files.withLock { $0.removeValue(forKey: name) != nil } }
}

@MainActor
final class SettingsCatalogueTests: XCTestCase {
    private static let moment = Date(timeIntervalSince1970: 1_767_225_600)

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "snapshots-\(UUID().uuidString)") ?? .standard
    }

    /// A source id that is the same on every run, so nothing on screen depends on a random one.
    private static func id(_ last: Int) -> UUID {
        UUID(uuidString: "5A1D0000-0000-4000-8000-00000000000\(last)") ?? UUID()
    }

    static let share = Source(
        id: id(1),
        displayName: "Living room NAS", kind: .networkShare, state: .connected,
        lastSuccessfulSync: moment, locator: "smb://nas.local/comics"
    )
    static let kavita = Source(
        id: id(2),
        displayName: "Kavita at home", kind: .kavitaServer, state: .connected,
        lastSuccessfulSync: moment, locator: "https://kavita.example.test"
    )
    static let folder = Source(
        id: id(3),
        displayName: "Comics", kind: .localFolder, state: .connected,
        lastSuccessfulSync: moment, locator: "/Comics"
    )
    static let catalogue = Source(
        id: id(4),
        displayName: "Standard Ebooks", kind: .opdsCatalog, state: .unreachable(since: moment),
        lastSuccessfulSync: moment, locator: "https://standardebooks.example.test/opds"
    )

    private var sources: [Source] { [Self.folder, Self.kavita, Self.share, Self.catalogue] }

    private struct Root<Content: View>: View {
        @State var settings = AppSettings()
        let content: (Binding<AppSettings>) -> Content
        var body: some View { content($settings) }
    }

    private func settingsView(
        _ settings: Binding<AppSettings>,
        opensAtDownloads: Bool = false,
        downloads: DownloadLibrary = DownloadLibrary(),
        bytesOnDisk: Int64 = 0
    ) -> SettingsView {
        SettingsView(
            settings: settings,
            readerStore: ReaderPreferences(defaults: defaults()),
            onReset: {},
            opensAtDownloads: opensAtDownloads,
            sources: sources,
            itemCount: { _ in 120 },
            downloads: downloads,
            bytesOnDisk: bytesOnDisk
        )
    }

    func testCatalogue09SettingsRoot() {
        assertCatalogue("09-settings-root") { Root { self.settingsView($0) } }
    }

    func testCatalogue10SourcesList() {
        assertCatalogue("10-sources-list") {
            NavigationStack {
                SourcesSettings(
                    sources: self.sources, itemCount: { _ in 120 }, isPartial: { _ in false },
                    onRemove: { _ in }, onRename: { _, _ in }
                )
                .navigationTitle("Your libraries")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    func testCatalogue11SourceDetail() {
        let diagnosis = SourceDiagnosis.of(
            Self.kavita, itemCount: 120,
            downloads: [
                Download(
                    id: "kavita-1", sourceID: Self.kavita.id, title: "The Long Field",
                    remote: URL(filePath: "/kavita/1"), mediaType: "application/vnd.comicbook+zip",
                    state: .finished, expectedBytes: 48_000_000, downloadedBytes: 48_000_000
                )
            ]
        )
        assertCatalogue("11-source-detail") {
            NavigationStack {
                SourceDetail(source: Self.kavita, diagnosis: diagnosis, perform: { _ in })
                    .navigationTitle(Self.kavita.displayName)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    func testCatalogue12SettingsSync() async throws {
        let suite = defaults()
        let progress = try ProgressStore.inMemory()
        let transfer = LibraryTransfer(
            archive: LibraryArchive(defaults: suite, progress: progress), secrets: NoSecrets()
        )
        let state = LibrarySyncState(defaults: suite)
        let place = MemoryPlace()
        let moment = Self.moment
        let runner = LibrarySyncRunner(
            places: SyncPlaceStore(defaults: suite),
            placeFor: { _ in place },
            sync: { try await transfer.sync(with: $0, state: state, appVersion: "1.0", at: moment) },
            now: { moment }
        )
        runner.chooseShare(Self.share.id)
        await runner.run(.chosen)
        assertCatalogue("12-settings-sync") {
            NavigationStack {
                List { SyncSettingsSection(runner: runner, sources: self.sources) }
                    .navigationTitle("Your libraries")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    func testCatalogue13DownloadsAndStorage() {
        let remote = URL(filePath: "/kavita/d")
        let downloads = DownloadLibrary(downloads: [
            Download(
                id: "a", sourceID: Self.kavita.id, title: "The Long Field", remote: remote,
                mediaType: "application/vnd.comicbook+zip", state: .finished,
                expectedBytes: 48_000_000, downloadedBytes: 48_000_000
            ),
            Download(
                id: "b", sourceID: Self.kavita.id, title: "Night Ferry 2", remote: remote,
                mediaType: "application/vnd.comicbook+zip", state: .finished,
                expectedBytes: 31_000_000, downloadedBytes: 31_000_000
            ),
        ])
        assertCatalogue("13-downloads-and-storage") {
            Root { self.settingsView($0, opensAtDownloads: true, downloads: downloads, bytesOnDisk: 79_000_000) }
        }
    }
}
