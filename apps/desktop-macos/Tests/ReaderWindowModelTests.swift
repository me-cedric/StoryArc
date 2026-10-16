import Foundation
import Testing

@testable import StoryArc

/// The window model of task 2.9: one window per publication, a second open focuses the
/// first, and a relaunch reopens what it can and names what it cannot.
@MainActor
@Suite("Reader window model")
struct ReaderWindowModelTests {
    private func target(_ id: String, path: String = "/Volumes/Comics/x.cbz") -> ReaderTarget {
        ReaderTarget(publicationID: id, path: path, title: id)
    }

    private func windows() throws -> (ReaderWindows, ScratchDefaults) {
        let scratch = try ScratchDefaults(prefix: "mac-windows-")
        let defaults = scratch.defaults
        return (ReaderWindows(defaults: defaults), scratch)
    }

    @Test("A target is Codable and Hashable, and equal by publication alone")
    func codableAndHashable() throws {
        let saga = target("saga", path: "/a/saga.cbz")
        let moved = target("saga", path: "/b/saga.cbz")
        let data = try JSONEncoder().encode(saga)
        let decoded = try JSONDecoder().decode(ReaderTarget.self, from: data)

        #expect(decoded == saga)
        #expect(decoded.path == "/a/saga.cbz")
        #expect(saga == moved)
        #expect(saga.hashValue == moved.hashValue)
        #expect(Set([saga, moved]).count == 1)
    }

    @Test("A second open of the same publication focuses the first window")
    func secondOpenFocuses() throws {
        let (windows, scratch) = try windows()
        defer { scratch.remove() }
        let defaults = scratch.defaults
        let saga = target("saga")

        #expect(windows.decide(saga) == .open(saga))
        windows.didOpen(saga)
        #expect(windows.decide(saga) == .focus(saga))
        #expect(windows.decide(target("monstress")) == .open(target("monstress")))

        windows.didClose(saga)
        #expect(windows.decide(saga) == .open(saga))
    }

    @Test("Open windows and their frames are saved, and a new instance reads them back")
    func sessionsPersist() throws {
        let (windows, scratch) = try windows()
        defer { scratch.remove() }
        let defaults = scratch.defaults
        let frame = CGRect(x: 10, y: 20, width: 800, height: 600)
        windows.didOpen(target("saga"))
        windows.didOpen(target("monstress"))
        windows.didPlace(target("saga"), at: frame)

        let saved = ReaderWindows(defaults: defaults).savedSessions()

        #expect(saved.map(\.target.publicationID) == ["saga", "monstress"])
        #expect(saved.first?.frame == frame)
        #expect(saved.last?.frame == nil)
    }

    @Test("Restoration reopens reachable windows and names the missing one")
    func restorationSkipsMissing() {
        let saved = [
            ReaderSession(target: target("saga"), frame: nil),
            ReaderSession(target: target("gone", path: "/Volumes/Away/gone.cbz"), frame: nil),
            ReaderSession(target: target("saga"), frame: nil),
        ]

        let plan = RestorationPlan.plan(saved: saved) { $0.publicationID != "gone" }

        #expect(plan.reopen.map(\.target.publicationID) == ["saga"])
        #expect(plan.missing.map(\.publicationID) == ["gone"])
    }

    @Test("A frame on a display that is gone is not reused")
    func frameOnAGoneDisplay() {
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let onMain = CGRect(x: 100, y: 100, width: 800, height: 600)
        let offEveryScreen = CGRect(x: 3000, y: 100, width: 800, height: 600)

        #expect(RestorationPlan.visibleFrame(onMain, screens: [main]) == onMain)
        #expect(RestorationPlan.visibleFrame(offEveryScreen, screens: [main]) == nil)
        #expect(RestorationPlan.visibleFrame(nil, screens: [main]) == nil)
    }
}
