import Foundation
import Testing

@testable import LibraryFeature

import StoryArcCore

/// What one pull re-fetches, and what it leaves alone.
///
/// `sources`' *Refreshing a source*: "when a reader pulls to refresh … the app re-fetches the
/// catalogue in the background". Android's pull called `rescan()` and nothing else, so a
/// reader who pulled on a shelf narrowed to a server got a folder walk and no catalogue fetch
/// at all. iOS asked every server and walked every folder on every pull, whatever the shelf
/// was showing, which is the other way to be wrong: a reader on a metered link paid for the
/// whole library because they pulled one shelf.
///
/// Both now refresh the sources the shelf is showing. A folder walk is local disk and costs no
/// data, so it runs whenever the shelf could hold a folder's publications; the network is
/// asked only when the shelf is showing something that is reached over one.
///
/// Android's `ShelfRefreshTest` holds this table case for case.
@Suite("A pull refreshes what the shelf is showing")
struct ShelfRefreshTests {

    private static func source(_ kind: SourceKind) -> Source {
        Source(displayName: "Fixture", kind: kind, state: .connected)
    }

    private static func registry(_ kinds: SourceKind...) -> SourceRegistry {
        kinds.reduce(SourceRegistry()) { $0.adding(Self.source($1)) }
    }

    @Test("The whole shelf walks the folders, because that costs no data")
    func everythingWalksTheFolders() {
        let registry = Self.registry(.kavitaServer)
        #expect(ShelfRefresh.of(.allSources, in: registry).walksFolders)
    }

    @Test("The whole shelf asks the network when something on it is reached over one")
    func everythingAsksTheNetwork() {
        #expect(ShelfRefresh.of(.allSources, in: Self.registry(.localFolder, .kavitaServer)).asksNetwork)
        #expect(ShelfRefresh.of(.allSources, in: Self.registry(.opdsCatalog)).asksNetwork)
        #expect(ShelfRefresh.of(.allSources, in: Self.registry(.networkShare)).asksNetwork)
    }

    @Test("A library of folders alone asks no network, however often it is pulled")
    func foldersAloneAskNothing() {
        #expect(!ShelfRefresh.of(.allSources, in: Self.registry(.localFolder)).asksNetwork)
        #expect(!ShelfRefresh.of(.allSources, in: Self.registry()).asksNetwork)
    }

    @Test(
        "A shelf narrowed to one server asks that server and skips the folder walk",
        arguments: [SourceKind.networkShare, .opdsCatalog, .kavitaServer]
    )
    func oneServerIsAskedAlone(_ kind: SourceKind) {
        let server = Self.source(kind)
        let registry = SourceRegistry().adding(server).adding(Self.source(.localFolder))
        let plan = ShelfRefresh.of(.source(server.id), in: registry)
        #expect(plan.asksNetwork)
        #expect(!plan.walksFolders, "a reader on a metered link paid for a folder walk as well")
    }

    @Test("A shelf narrowed to one folder walks the folders and asks no network")
    func oneFolderAsksNoNetwork() {
        let folder = Self.source(.localFolder)
        let registry = SourceRegistry().adding(folder).adding(Self.source(.kavitaServer))
        let plan = ShelfRefresh.of(.source(folder.id), in: registry)
        #expect(plan.walksFolders)
        #expect(!plan.asksNetwork, "a folder is on this device, so nothing has to be asked")
    }

    /// The library's own source, read from where this test file is.
    ///
    /// Reached from `#filePath` rather than found: this repository nests agent worktrees at
    /// `.claude/worktrees/`, and a walk that looks upwards for a marker climbs out of the one
    /// under test.
    private static let viewSource: String = {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/LibraryFeature/LibraryView.swift")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            fatalError("LibraryView.swift is not readable at \(file.path)")
        }
        return text
    }()

    /// That the pull consults the plan, which is the half a pure decision cannot prove.
    ///
    /// A rule asserted and never called is indistinguishable from a rule that works —
    /// AGENTS.md section 5 catalogues three of them in this repository. The honest test drags
    /// a real shelf down on a device; there is none here, so this reads the source instead and
    /// says only what source text may honestly say: that the call exists, and that the two
    /// refreshes sit after it. Android's `ShelfRefreshTest` makes the same second choice.
    @Test("The pull consults the plan before it refreshes anything")
    func thePullConsultsThePlan() throws {
        let text = Self.viewSource
        let start = try #require(text.range(of: ".refreshable {"), "LibraryView no longer pulls")
        let body = text[start.lowerBound...]
        let plan = try #require(
            body.range(of: "ShelfRefresh.of("),
            "the pull refreshes without asking what the shelf is showing"
        )
        let network = try #require(
            body.range(of: "resolveSources("),
            "the pull no longer re-fetches a server, which is the defect Android had"
        )
        let walk = try #require(body.range(of: "rescan()"), "the pull no longer walks a folder")
        #expect(plan.lowerBound < network.lowerBound, "the servers are asked before the plan is")
        #expect(plan.lowerBound < walk.lowerBound, "the folders are walked before the plan is")
    }

    @Test("A scope naming a source that has gone is the whole shelf again")
    func aStaleScopeIsTheWholeShelf() {
        // `LibraryScope.resolved(in:)` already answers this for the view; the plan asks it
        // too, so a scope restored at launch that points at a removed source refreshes the
        // library rather than nothing at all.
        let registry = Self.registry(.localFolder, .kavitaServer)
        let plan = ShelfRefresh.of(.source(UUID()), in: registry)
        #expect(plan == ShelfRefresh.of(.allSources, in: registry))
    }
}
