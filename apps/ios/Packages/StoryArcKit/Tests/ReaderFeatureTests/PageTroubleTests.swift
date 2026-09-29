import Foundation
import Testing

import Formats
import StoryArcCore
@testable import ReaderFeature

/// Whether a read may go ahead, decided by the test.
///
/// `hold` keeps each read waiting until the test lets it through, one at a time or all at
/// once. That is the only way to put the reader in the state `network-share`'s notice is
/// about: a page on screen whose bytes have not arrived yet.
private actor Gate {
    enum Mode { case pass, fail, hold }

    private var mode = Mode.pass
    private var held: [CheckedContinuation<Bool, Never>] = []

    var heldCount: Int { held.count }

    func set(_ next: Mode) {
        mode = next
        guard next != .hold else { return }
        let waiting = held
        held = []
        waiting.forEach { $0.resume(returning: next == .pass) }
    }

    func releaseOne() {
        guard !held.isEmpty else { return }
        held.removeFirst().resume(returning: true)
    }

    func enter() async -> Bool {
        switch mode {
        case .pass: true
        case .fail: false
        case .hold: await withCheckedContinuation { held.append($0) }
        }
    }
}

/// A fixture archive served over the `smb` scheme, through a ``Gate``.
private struct GatedSource: RandomAccessSource {
    let file: FileSource
    let gate: Gate

    var length: Int64 { file.length }

    func read(offset: Int64, count: Int) async throws -> Data {
        guard await gate.enter() else { throw SourceError.unreadable }
        return try await file.read(offset: offset, count: count)
    }
}

/// The `smb` opener this suite registers, one gate per host so tests can run side by side.
private final class TestShare: @unchecked Sendable {
    static let shared = TestShare()

    private let lock = NSLock()
    private var gates: [String: Gate] = [:]

    private init() {
        ComicArchiveOpener.register(scheme: "smb") { url in
            guard let host = url.host(), let gate = TestShare.shared.gate(for: host) else {
                throw SourceError.unreadable
            }
            return GatedSource(file: try FileSource(url: Self.fixture), gate: gate)
        }
    }

    private func gate(for host: String) -> Gate? {
        lock.withLock { gates[host] }
    }

    func address(for gate: Gate) throws -> URL {
        let host = "gate-\(UUID().uuidString.lowercased())"
        lock.withLock { gates[host] = gate }
        return try #require(URL(string: "smb://\(host)/Comics/natural-sort.cbz"))
    }

    private static let fixture: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: candidate.appending(path: "manifest.json").path) {
                return candidate.appending(path: "comics/natural-sort.cbz")
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()
}

/// `network-share`'s *Connection drops while reading*, driven through the reader itself.
///
/// The notice counts from ``ReaderModel/pageBlockedSince``: from when the page on screen
/// began to wait, and only for that page. The model here reads a real fixture archive over
/// the `smb` scheme, through a gate that holds or fails each read on cue, so every claim is
/// made through `go(to:)`, `decode(_:)` and ``ReaderModel/recoverCurrentPage()`` rather than
/// by setting the two dates by hand.
@MainActor
@Suite("The network notice counts the page on screen's own trouble")
struct PageTroubleTests {

    private func openedOverAShare() async throws -> (ReaderModel, Gate) {
        let gate = Gate()
        let url = try TestShare.shared.address(for: gate)
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: url.absoluteString),
            format: .cbz,
            displayTitle: "Natural Sort",
            origin: .inferred
        )
        let model = ReaderModel(publication: publication, url: url)
        await model.open(maxPixelSize: 256)
        try #require(model.pages.count == 12, "the fixture did not open over the gated share")
        #expect(model.pageBlockedSince == nil)
        return (model, gate)
    }

    private struct NeverHeld: Error {}

    /// Polls, because every read here finishes on a task of its own.
    private func until(_ condition: () async -> Bool) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw NeverHeld()
    }

    @Test("The page on screen counts from when its read began, while the read is open")
    func aReadStillOpenIsCounted() async throws {
        let (model, gate) = try await openedOverAShare()
        await gate.set(.hold)
        let before = Date()

        let turn = Task { await model.go(to: 5) }
        try await until { model.pageBlockedSince != nil }
        #expect(try #require(model.pageBlockedSince) >= before)

        await gate.set(.pass)
        await turn.value
        #expect(model.image(at: 5) != nil)
        #expect(model.pageBlockedSince == nil)
    }

    @Test("A page turned to while its prefetch is still reading counts from the turn")
    func turningToAPageStillReading() async throws {
        let (model, gate) = try await openedOverAShare()
        await gate.set(.hold)
        let first = Task { await model.go(to: 5) }

        // Page 5 through, one read at a time, until it lands. The read that holds after it
        // is a neighbour's prefetch.
        try await until { await gate.heldCount > 0 }
        while model.image(at: 5) == nil {
            await gate.releaseOne()
            try await until {
                if model.image(at: 5) != nil { return true }
                return await gate.heldCount > 0
            }
        }
        try await until { await gate.heldCount > 0 }
        let neighbour = try #require(model.reading.first { $0 != 5 })
        #expect(model.pageBlockedSince == nil, "a neighbour's prefetch was counted as the page on screen's")

        let second = Task { await model.go(to: neighbour) }
        try await until { model.currentIndex == neighbour }
        #expect(model.pageBlockedSince != nil, "the page turned to waits on a read already under way")

        await gate.set(.pass)
        await first.value
        await second.value
        #expect(model.image(at: neighbour) != nil)
        #expect(model.pageBlockedSince == nil)
    }

    @Test("A failed read, and a retry that fails again, keep the time the page began to wait")
    func failureKeepsTheWaitStart() async throws {
        let (model, gate) = try await openedOverAShare()
        await gate.set(.hold)
        let turn = Task { await model.go(to: 5) }
        try await until { model.pageBlockedSince != nil }
        let began = model.pageBlockedSince

        await gate.set(.fail)
        await turn.value
        #expect(model.image(at: 5) == nil)
        #expect(model.pageBlockedSince == began, "the notice restarted when the read gave up")

        await model.recoverCurrentPage()
        #expect(model.pageBlockedSince == began, "a retry restarted the notice")
    }

    @Test("The page on screen is read again once the share answers, without a turn")
    func recoveryReadsTheCurrentPageAgain() async throws {
        let (model, gate) = try await openedOverAShare()
        await gate.set(.fail)
        await model.go(to: 5)
        #expect(model.image(at: 5) == nil)
        #expect(model.pageBlockedSince != nil)

        await gate.set(.pass)
        await model.recoverCurrentPage()
        #expect(model.image(at: 5) != nil)
        #expect(model.pageBlockedSince == nil)
    }

    @Test("A turn away forgets the trouble of the page being left")
    func turningAwayForgetsTheTrouble() async throws {
        let (model, gate) = try await openedOverAShare()
        await gate.set(.fail)
        await model.go(to: 5)
        #expect(model.pageBlockedSince != nil)

        await gate.set(.pass)
        await model.go(to: 9)
        #expect(model.pageBlockedSince == nil)
    }
}
