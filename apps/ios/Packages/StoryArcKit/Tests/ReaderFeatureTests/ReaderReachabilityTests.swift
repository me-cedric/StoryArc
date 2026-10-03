import Foundation
import Testing

import Formats
import StoryArcCore
@testable import ReaderFeature

/// An archive whose every read fails the way the test says.
private struct Failing: ComicArchiveReading {
    let failure: any Error
    var pages: [PageEntry] { [PageEntry(path: "001.jpg")] }
    var skippedPageCount: Int { 0 }

    func data(for page: PageEntry) async throws -> Data { throw failure }
}

private struct Gone: SourceReachabilityError {
    var meansUnreachable: Bool { true }
}

private struct Damaged: Error {}

/// The reports one page read posts, collected on the posting thread.
private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [UUID] = []

    var seen: [UUID] { lock.withLock { ids } }

    func add(_ id: UUID) { lock.withLock { ids.append(id) } }
}

/// `network-share`'s *Network changes*, second clause: the reader is already open when the
/// path moves, and the next page read cannot reach the share. That read is where the
/// library is told, through ``ReaderModel/pageData(of:in:sourceID:)``, the function the
/// reader's own decode calls.
@Suite("Reader reachability")
struct ReaderReachabilityTests {

    private func reports(reading failure: any Error, sourceID: UUID?) async -> [UUID] {
        let reports = Reports()
        let observer = NotificationCenter.default.addObserver(
            forName: SourceReachabilityEvents.unreachable, object: nil, queue: nil
        ) { note in
            if let id = SourceReachabilityEvents.sourceID(in: note) { reports.add(id) }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let data = await ReaderModel.pageData(
            of: PageEntry(path: "001.jpg"), in: Failing(failure: failure), sourceID: sourceID
        )
        #expect(data == nil)
        return reports.seen
    }

    @Test("A page read that finds the share gone reports its source")
    func goneShareIsReported() async {
        let sourceID = UUID()
        let seen = await reports(reading: Gone(), sourceID: sourceID)
        #expect(seen.contains(sourceID))
    }

    @Test("A damaged page is not the share being gone")
    func damagedPageIsNotReported() async {
        let sourceID = UUID()
        let seen = await reports(reading: Damaged(), sourceID: sourceID)
        #expect(!seen.contains(sourceID))
    }

    @Test("A publication with no source has nothing to report")
    func sourcelessPublicationReportsNothing() async {
        let seen = await reports(reading: Gone(), sourceID: nil)
        #expect(seen.isEmpty)
    }
}
