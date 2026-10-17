import Foundation
import Testing

@testable import StoryArc

/// The bookmark states of task 2.19: available, needing access, offline, and back.
@Suite("Folder sources")
struct FolderSourceTests {
    private let saga = URL(filePath: "/Volumes/Comics/Saga", directoryHint: .isDirectory)
    private let away = URL(filePath: "/Volumes/Away/Monstress", directoryHint: .isDirectory)
    private var sagaFolder: RememberedFolder { RememberedFolder(key: "k1", name: "Saga", url: saga) }
    private var awayFolder: RememberedFolder { RememberedFolder(key: "k2", name: "Monstress", url: away) }

    @Test("A reachable folder is available, an unreachable one is offline, a stale one needs access")
    func threeStates() {
        let sources = FolderSourceStates.resolve(
            folders: [sagaFolder, awayFolder],
            stale: ["Paper Girls"]
        ) { $0 == saga }

        #expect(sources.map(\.state) == [.available, .offline, .needsAccess])
        #expect(sources.map(\.name) == ["Saga", "Monstress", "Paper Girls"])
        #expect(sources[1].isGrey && sources[2].isGrey && !sources[0].isGrey)
        #expect(sources[2].url == nil)
    }

    @Test("An offline volume that returns brings its source back by itself")
    func volumeReturns() {
        let before = FolderSourceStates.resolve(
            folders: [awayFolder], stale: ["Paper Girls"]
        ) { _ in false }
        #expect(before.first?.state == .offline)

        let after = FolderSourceStates.revisited(before) { _ in true }

        #expect(after.first?.state == .available)
        // Access that was withdrawn does not come back with a volume: the reader re-picks it.
        #expect(after.last?.state == .needsAccess)
    }

    @Test("A source keeps its place in the list whatever its state")
    func keepsItsPlace() {
        let sources = FolderSourceStates.resolve(
            folders: [sagaFolder, awayFolder], stale: []
        ) { _ in false }
        let back = FolderSourceStates.revisited(sources) { $0 == away }
        #expect(back.map(\.key) == ["k1", "k2"])
        #expect(back.map(\.state) == [.offline, .available])
    }
}
