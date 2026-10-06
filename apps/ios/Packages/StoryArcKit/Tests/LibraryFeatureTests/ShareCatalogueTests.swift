import Foundation
import Formats
import StoryArcCore
import Testing

@testable import LibraryFeature

/// D28: a share row catalogued from its own headers rather than from its file name.
///
/// The share itself is stood in for by a fixture behind ``ShareCatalogue/catalogued(_:openedBy:)``'s
/// opener, which is what that parameter is for — the decision being asserted is what a header
/// read changes about a row, and that has nothing to do with SMB.
@Suite("Share rows catalogued from their headers")
struct ShareCatalogueTests {

    private let sourceID = UUID()

    /// A row exactly as ``SmbContributor`` builds one: the extension's claim, the optimistic
    /// default, no page count and no cover.
    private func row(
        named name: String,
        format: PublicationFormat,
        streaming: StreamingCapability = .streams
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(
                normalizedPath: "smb://nas.local/Comics/Lantern%20Green/\(name)"
            ),
            format: format,
            displayTitle: (name as NSString).deletingPathExtension,
            origin: .inferred,
            streaming: streaming,
            sourceID: sourceID,
            fileSize: 400_000_000
        )
    }

    private func fixture(_ relativePath: String) -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let corpus = directory.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: corpus.appending(path: "manifest.json").path) {
                return corpus.appending(path: relativePath)
            }
            directory = directory.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }

    private func catalogued(_ row: Publication, as relativePath: String) async -> Publication? {
        let url = fixture(relativePath)
        return await ShareCatalogue.catalogued(row) { _ in try FileSource(url: url) }
    }

    @Test("A share row's format comes from its headers, not from its extension")
    func detectsTheRealContainer() async throws {
        let found = try #require(
            await catalogued(row(named: "mislabelled-zip.cbr", format: .cbr), as: "comics/mislabelled-zip.cbr")
        )

        #expect(found.format == .cbz)
        #expect(found.pageCount == 3)
        #expect(found.coverPath == "page1.png")
        #expect(found.streaming == .streams)
    }

    @Test("A solid RAR4 on a share is refused on the shelf, before a reader taps it")
    func namesARefusalBeforeTheTap() async throws {
        let found = try #require(
            await catalogued(row(named: "rar4-solid.cbr", format: .cbr), as: "comics/rar4-solid.cbr")
        )

        #expect(found.streaming == .refused)
        #expect(!found.isOpenable)
    }

    @Test("What only the share's walk knew survives the merge")
    func keepsWhatTheWalkKnew() async throws {
        let walked = row(named: "mislabelled-zip.cbr", format: .cbr)
        let found = try #require(await catalogued(walked, as: "comics/mislabelled-zip.cbr"))

        #expect(found.id == walked.id)
        #expect(found.sourceID == sourceID)
        #expect(found.fileSize == 400_000_000)
    }

    @Test("A catalogued row is not asked for its headers a second time")
    func asksOnce() async throws {
        let walked = row(named: "mislabelled-zip.cbr", format: .cbr)
        #expect(ShareCatalogue.needsCataloguing(walked))

        let found = try #require(await catalogued(walked, as: "comics/mislabelled-zip.cbr"))

        #expect(!ShareCatalogue.needsCataloguing(found))
    }

    @Test("A row that is already refused by name is left alone")
    func leavesARefusedRowAlone() {
        let seven = row(named: "refused.cb7", format: .cb7, streaming: .refused)

        #expect(!ShareCatalogue.needsCataloguing(seven))
    }

    @Test("A publication on this device is not a share row")
    func ignoresALocalPublication() {
        let local = Publication(
            identity: PublicationIdentity(normalizedPath: "/Users/reader/Comics/natural-sort.cbz"),
            format: .cbz,
            displayTitle: "natural-sort",
            origin: .inferred
        )

        #expect(!ShareCatalogue.needsCataloguing(local))
    }

    @Test("A share that does not answer leaves the row as the walk left it")
    func anUnreachableShareChangesNothing() async {
        let walked = row(named: "mislabelled-zip.cbr", format: .cbr)

        let found = await ShareCatalogue.catalogued(walked) { _ in throw SourceError.unreadable }

        #expect(found == nil)
    }
}
