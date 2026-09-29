import Foundation
import Testing

@testable import StoryArcCore

/// ``Download/finishedCopy(of:remote:mediaType:bytes:completedAt:)`` — the record
/// `keptForOffline` writes for a publication just copied off a share in one pass.
///
/// Lifted out of the app layer so the fields that make a record *this publication's* are a
/// rule with a name and a test, not an app-layer literal nothing else can check. The defect
/// this closes wrote no record at all: the file existed and nothing on *On device* or in the
/// storage total knew it did.
@Suite("A finished copy is recorded as one, from the publication it copied")
struct DownloadFinishedCopyTests {
    private func publication(sourceID: UUID? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "smb://nas/share/Comics/x.cbz"),
            format: .cbz,
            displayTitle: "Bright Panels #1",
            origin: .inferred,
            sourceID: sourceID
        )
    }

    @Test("The record carries the publication's own identity, title and source")
    func carriesTheIdentity() {
        let source = UUID()
        let one = publication(sourceID: source)
        let remote = URL(string: "smb://nas/share/Comics/x.cbz")!
        let record = Download.finishedCopy(
            of: one, remote: remote, mediaType: "application/vnd.comicbook+zip", bytes: 4096
        )
        #expect(record.id == one.id)
        #expect(record.sourceID == source)
        #expect(record.title == "Bright Panels #1")
        #expect(record.mediaType == "application/vnd.comicbook+zip")
        #expect(record.remote == remote)
    }

    @Test("The record is already finished, with both byte counts equal to what was copied")
    func isAlreadyFinished() {
        let record = Download.finishedCopy(
            of: publication(),
            remote: URL(string: "smb://nas/share/Comics/x.cbz")!,
            mediaType: "application/vnd.comicbook+zip",
            bytes: 12_345
        )
        #expect(record.state == .finished)
        #expect(record.expectedBytes == 12_345)
        #expect(record.downloadedBytes == 12_345)
        #expect(record.completedAt != nil)
    }
}
