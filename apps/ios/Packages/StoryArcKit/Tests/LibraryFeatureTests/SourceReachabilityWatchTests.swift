import Foundation
import Testing

@testable import LibraryFeature
import Smb
import StoryArcCore

/// `network-share`'s *Network changes*, second clause, on the library's side: a share that
/// an open reader found gone is marked unreachable, and the moment it went is kept.
@MainActor
@Suite("Source reachability watch")
struct SourceReachabilityWatchTests {

    private func library(holding source: Source) -> LibraryModel {
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [source])
        return model
    }

    @Test("A reported share becomes unreachable")
    func reportedShareIsUnreachable() {
        let share = Source(displayName: "Office NAS", kind: .networkShare)
        let model = library(holding: share)
        let moment = Date(timeIntervalSince1970: 1_000)

        model.noteUnreachable(share.id, at: moment)

        #expect(model.registry[share.id]?.state == .unreachable(since: moment))
    }

    @Test("A repeated report keeps the moment the share went")
    func repeatedReportKeepsTheMoment() {
        var share = Source(displayName: "Office NAS", kind: .networkShare)
        let first = Date(timeIntervalSince1970: 1_000)
        share.state = .unreachable(since: first)
        let model = library(holding: share)

        model.noteUnreachable(share.id, at: Date(timeIntervalSince1970: 2_000))

        #expect(model.registry[share.id]?.state == .unreachable(since: first))
    }

    @Test("The watch applies a report the reader posts")
    func watchAppliesAPostedReport() async throws {
        let share = Source(displayName: "Office NAS", kind: .networkShare)
        let model = library(holding: share)
        model.watchSourceReachability()

        SourceReachabilityEvents.reportUnreachable(share.id)

        for _ in 0..<100 where !Self.isUnreachable(model.registry[share.id]) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(Self.isUnreachable(model.registry[share.id]))
    }

    @Test("Only a host that stopped answering means the share is gone")
    func onlyHostUnreachableMeansGone() {
        #expect(SmbError.hostUnreachable.meansUnreachable)
        #expect(!SmbError.shareNotFound.meansUnreachable)
        #expect(!SmbError.authenticationRejected.meansUnreachable)
    }

    @Test("A publication opened from a share's browser is filed under that share")
    func browserOpenIsFiledUnderTheShare() {
        let share = UUID()
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: "smb://nas/Comics/a.cbz"),
            format: .cbz,
            displayTitle: "a.cbz",
            origin: .inferred
        )

        #expect(publication.filed(under: share).sourceID == share)
    }

    @Test("A launch starts the watch")
    func launchStartsTheWatch() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { root.deleteLastPathComponent() }
        let code = try String(
            contentsOf: root.appending(path: "Sources/LibraryFeature/LibraryRestore.swift"), encoding: .utf8
        )
        #expect(code.contains("watchSourceReachability()"))
    }

    private static func isUnreachable(_ source: Source?) -> Bool {
        if case .unreachable = source?.state { return true }
        return false
    }
}
