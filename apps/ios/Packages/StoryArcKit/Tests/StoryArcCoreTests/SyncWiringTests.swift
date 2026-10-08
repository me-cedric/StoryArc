import Foundation
import Testing

/// `library-sync` tasks 4.1, 4.2 and 4.3: where the app calls the sync runner.
///
/// **This reads source text**, for the reason ``ResumeWiringTests`` records: `project.yml`
/// declares no app unit-test target, so nothing in this package can drive `StoryArcApp`. The
/// runner's own rules are `LibrarySyncRunnerTests`'; this is a tripwire that the app still calls
/// it at the moments the spec names, and that the plist keys task 4.3 needs are declared.
@Suite("Sync wiring")
struct SyncWiringTests {

    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory
    }()

    private func source(_ relativePath: String) throws -> String {
        let url = Self.appleRoot.appendingPathComponent(relativePath)
        return try #require(try? String(contentsOf: url, encoding: .utf8), "\(url.path) could not be read")
    }

    @Test("The foreground asks for a sync, in a task of its own")
    func foreground() throws {
        let app = try source("App/StoryArcApp.swift")
        #expect(app.contains(".onChange(of: scenePhase, initial: true) { _, phase in syncPhaseChanged(to: phase) }"))
        let wiring = try source("App/LibrarySyncWiring.swift")
        #expect(wiring.contains("case .active:\n            Task { await syncRunner.run(.foreground) }"))
    }

    @Test("Closing a reader syncs that publication, unless Kavita keeps it")
    func leaving() throws {
        let actions = try source("App/StoryArcAppActions.swift")
        #expect(actions.contains("if let closed { await syncAfterLeaving(closed.publication) }"))
        let wiring = try source("App/LibrarySyncWiring.swift")
        #expect(wiring.contains("leftPublication(ownedByKavita: kavitaProgress.origin(of: publication.id) != nil)"))
    }

    @Test("The background refresh is registered, declared, and runs the same sync")
    func background() throws {
        let app = try source("App/StoryArcApp.swift")
        #expect(app.contains(".backgroundTask(.appRefresh(Self.syncRefreshTask))"))
        let wiring = try source("App/LibrarySyncWiring.swift")
        #expect(wiring.contains("static let syncRefreshTask = \"app.storyarc.sync\""))
        #expect(wiring.contains("await runner.run(.background)"))
        let project = try source("project.yml")
        #expect(project.contains("          - audio\n          - fetch\n"))
        #expect(project.contains("BGTaskSchedulerPermittedIdentifiers:\n          - app.storyarc.sync"))
    }

    @Test("After a sync the app reads its settings and its library again")
    func reload() throws {
        let app = try source("App/StoryArcApp.swift")
        #expect(app.contains(".task { syncRunner?.onSynced = { syncWroteTheStores() } }"))
        let wiring = try source("App/LibrarySyncWiring.swift")
        #expect(wiring.contains("settings = settingsStore.settings()"))
        #expect(wiring.contains("Task { await library.reloadAfterImport() }"))
    }
}
