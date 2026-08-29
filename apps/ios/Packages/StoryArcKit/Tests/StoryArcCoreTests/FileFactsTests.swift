import Foundation
import Testing

@testable import StoryArcCore

/// When a publication may be trusted rather than re-read.
///
/// `local-library` asks a returning app to reconcile "by comparing file modification times
/// and sizes rather than re-reading every archive". The risk in that sentence is not the
/// comparison — it is the *unknowns*, where trusting one costs a library that disagrees
/// with the disk and never finds out.
///
/// Android's `FileFactsTest` asserts the same table.
@Suite("File facts")
struct FileFactsTests {

    private let moment = Date(timeIntervalSince1970: 1_700_000_000)

    private func publication(size: Int64? = 1024, modified: Date? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/bone.cbz"),
            format: .cbz,
            displayTitle: "Bone",
            origin: .embedded,
            fileSize: size,
            modifiedAt: modified
        )
    }

    @Test("Same size and same moment is unchanged")
    func unchanged() {
        #expect(publication(modified: moment).matchesFile(size: 1024, modifiedAt: moment))
    }

    @Test("A different size is a different file")
    func sizeDiffers() {
        #expect(!publication(modified: moment).matchesFile(size: 2048, modifiedAt: moment))
    }

    @Test("A file written since is re-read even at the same size")
    func modifiedDiffers() {
        // The case that makes size alone insufficient: an editor that rewrites a container
        // in place can leave its length exactly as it was.
        #expect(
            !publication(modified: moment)
                .matchesFile(size: 1024, modifiedAt: moment.addingTimeInterval(60))
        )
    }

    @Test("Anything unknown is re-read rather than trusted")
    func unknownsAreNotAMatch() {
        // A publication indexed before these facts were recorded.
        #expect(!publication(size: nil, modified: moment).matchesFile(size: 1024, modifiedAt: moment))
        #expect(!publication(modified: nil).matchesFile(size: 1024, modifiedAt: moment))
        // A file the walk could not stat.
        #expect(!publication(modified: moment).matchesFile(size: nil, modifiedAt: moment))
        #expect(!publication(modified: moment).matchesFile(size: 1024, modifiedAt: nil))
    }
}
