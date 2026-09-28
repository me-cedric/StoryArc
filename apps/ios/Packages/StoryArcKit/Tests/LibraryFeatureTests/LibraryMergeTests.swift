import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// Which answer a row keeps when the library meets the same publication twice.
///
/// `library-browsing`, *A publication that is also downloaded*: a publication a source offers
/// and the device holds "is one row, not two, and that row is readable with no network". Two
/// rules make that true, and both live here:
///
/// 1. ``LibraryModel/adopt(_:from:)`` files a second find under the row already on the shelf,
///    because ``PublicationIdentity`` decides what a publication is and a path does not.
/// 2. ``LibraryMerge/merged(existing:found:sourceID:hasFile:)`` decides which description that
///    one row carries. A server owns its answer and may correct itself; a file on disk does
///    not, so a downloaded copy keeps the metadata read out of the file.
///
/// **Nothing asserted either on this platform.** Android's `LibraryMergeTest` held the same
/// table from the day the type was written and its iOS twin was shipped bare, so the 2026-09-12
/// recount scored the scenario `built, asserted by nothing`. A rewrite of `merged` that
/// re-described a downloaded file from a stale catalogue would have passed every test in this
/// package.
@Suite("The same publication met twice is one row")
@MainActor
struct LibraryMergeTests {

    private static let server = UUID()
    private static let folder = UUID()

    private func publication(
        _ title: String,
        origin: MetadataOrigin,
        path: String? = nil,
        remoteID: String = "chapter:1"
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(
                serverIdentifier: .init(sourceID: Self.server, remoteID: remoteID),
                normalizedPath: path
            ),
            format: .cbz,
            displayTitle: title,
            origin: origin
        )
    }

    // MARK: - Which description the row carries

    @Test("A server's newer answer replaces a stale one")
    func aServerCorrectsItself() {
        // The defect this rule was written for: a chapter cached as "-100000" stayed that way
        // after the code producing it was fixed, because a re-read only changed attribution.
        let merged = LibraryMerge.merged(
            existing: publication("-100000", origin: .authoritative),
            found: publication("Green Lantern", origin: .authoritative),
            sourceID: Self.server,
            hasFile: false
        )

        #expect(merged.displayTitle == "Green Lantern")
    }

    @Test("A downloaded file's own metadata is not overwritten by a description of it")
    func aDownloadedFileWins() {
        // The scenario itself. The row is the downloaded copy, and it stays the downloaded
        // copy: a server's catalogue describes the book, the file *is* the book.
        let merged = LibraryMerge.merged(
            existing: publication("From the file", origin: .embedded, path: "/a.cbz"),
            found: publication("From the server", origin: .authoritative),
            sourceID: Self.server,
            hasFile: true
        )

        #expect(merged.displayTitle == "From the file")
    }

    @Test("The row keeps its own identity, so nothing stored against it moves")
    func theRowKeepsItsKey() {
        // Reading progress, bookmarks and shelf membership are all filed under a
        // publication's key. A merge that changed the key would strand every one of them.
        // The find carries a key of its own — a re-read that learned a path the first read
        // did not. Two identical identities would make this case unable to fail.
        let existing = publication("old", origin: .authoritative)
        let found = publication("new", origin: .authoritative, path: "/late/path.cbz")
        #expect(found.identity != existing.identity, "the fixture must offer a second key")

        let merged = LibraryMerge.merged(
            existing: existing,
            found: found,
            sourceID: Self.server,
            hasFile: false
        )

        #expect(merged.identity == existing.identity)
        #expect(merged.id == existing.id)
    }

    @Test("A scanned file re-found is re-attributed and nothing else")
    func aScannedFileIsOnlyReattributed() {
        let merged = LibraryMerge.merged(
            existing: publication("A comic", origin: .embedded, path: "/a.cbz"),
            found: publication("A comic", origin: .embedded, path: "/a.cbz"),
            sourceID: Self.server,
            hasFile: true
        )

        #expect(merged.displayTitle == "A comic")
        #expect(merged.sourceID == Self.server)
    }

    // MARK: - Whether a find replaces the row at all

    @Test("A source re-read does not lose to itself")
    func aSourceDoesNotLoseToItself() {
        // ``SourcePrecedence`` answers *which of two sources wins*, strictly. A source
        // compared with itself lost that comparison, so a refresh could never correct a row
        // it had written — which is the bug ``LibraryMerge/replaces(_:over:in:)`` exists for.
        #expect(LibraryMerge.replaces(Self.server, over: Self.server, in: []))
    }

    // MARK: - One row, not two

    @Test("A publication a server offers and the device holds is one row")
    func aDownloadedServerTitleIsOneRow() {
        let model = LibraryModel()
        let offered = publication("Bone", origin: .authoritative)
        var downloaded = offered
        downloaded.identity = PublicationIdentity(
            serverIdentifier: .init(sourceID: Self.server, remoteID: "chapter:1"),
            normalizedPath: "/downloads/bone.cbz"
        )

        model.adopt(offered, from: Self.server)
        model.adopt(downloaded, from: Self.server)

        #expect(model.publications.count == 1)
    }

    @Test("Two different publications from one source are two rows")
    func twoTitlesStayTwoRows() {
        // The other side of the same rule, so the case above cannot pass by collapsing
        // everything a source offers into one cell.
        let model = LibraryModel()

        model.adopt(publication("Bone", origin: .authoritative, remoteID: "chapter:1"), from: Self.server)
        model.adopt(publication("Akira", origin: .authoritative, remoteID: "chapter:2"), from: Self.server)

        #expect(model.publications.count == 2)
    }

    @Test("The one row is the one with the file, so it opens with no network")
    func theSurvivingRowKnowsItsFile() {
        // "That row is readable with no network" is the second half of the scenario, and it
        // is decided by which location the row is filed under rather than by its metadata.
        let model = LibraryModel()
        let offered = publication("Bone", origin: .authoritative)
        var downloaded = offered
        downloaded.identity = PublicationIdentity(
            serverIdentifier: .init(sourceID: Self.server, remoteID: "chapter:1"),
            normalizedPath: "/downloads/bone.cbz"
        )

        model.adopt(offered, from: Self.server)
        model.adopt(downloaded, from: Self.server)

        let row = try? #require(model.publications.first)
        #expect(model.locations[row?.id ?? ""]?.path == "/downloads/bone.cbz")
    }
}
