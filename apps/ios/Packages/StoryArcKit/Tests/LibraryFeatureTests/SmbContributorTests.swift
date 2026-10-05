import Foundation
import Smb
import StoryArcCore
import Testing

@testable import LibraryFeature

/// What one file on a share looks like as a row.
///
/// A share is the one source that cannot be asked — it is a filesystem, walked. Three things
/// follow, and all three are asserted here: the row is identified by the share's own `smb://`
/// address for the file, not the bare path `SmbClient.list` returns — a location that is not
/// a real address reads as local, so the shelf used to count a row nobody had downloaded as
/// already on the device, and opening it handed the reader a path that existed nowhere on
/// the filesystem; a share's copy and a downloaded copy still fold together, because the
/// address is still one identity per file; and the metadata is the filename's and says so,
/// because reading the file's own would mean fetching the archive. Android's
/// `SmbContributorTest` makes the same claims.
struct SmbContributorTests {

    private let source = UUID()
    private let address = SmbAddress(host: "nas.local", share: "Comics")

    private func row(
        _ name: String,
        folder: String = "comics/Lantern Green",
        address: SmbAddress? = nil
    ) -> Publication? {
        SmbContributor.publication(
            source: source,
            entry: SmbEntry(name: name, path: "\(folder)/\(name)", isDirectory: false, length: 1),
            address: address ?? self.address,
            folder: folder
        )
    }

    @Test("A file is identified by the share's own address for it, not its bare path")
    func identity() {
        let publication = row("Lantern Green 043.cbz")

        #expect(
            publication?.identity.normalizedPath
                == "smb://nas.local/Comics/comics/Lantern%20Green/Lantern%20Green%20043.cbz"
        )
        // `PublicationAccess.isRemote` matches a location by its scheme prefix — a plain
        // path answers false and the shelf reads the row as already on the device.
        #expect(publication?.identity.normalizedPath?.hasPrefix("smb://") == true)
        #expect(publication?.identity.serverIdentifier == nil)
        #expect(publication?.sourceID == source)
    }

    @Test("A row states the size the share already stated, for free")
    func statesItsSize() {
        // `publication-formats` asks the download offer on the publication page to state
        // the size, and a directory entry already carries its own length — so the share
        // walk hands it over rather than leaving the reader to guess.
        let publication = SmbContributor.publication(
            source: source,
            entry: SmbEntry(
                name: "Lantern Green 043.cbz",
                path: "comics/Lantern Green/Lantern Green 043.cbz",
                isDirectory: false,
                length: 400_000_000
            ),
            address: address,
            folder: "comics/Lantern Green"
        )

        #expect(publication?.fileSize == 400_000_000)
    }

    @Test("A row under a configured root opens through the reader's own reading of its address")
    func rootRoundTrips() throws {
        // `entry.path` is relative to the share and so repeats the root the reader picked. The
        // opener strips the source's address, root and all, and hands the share the rest — so
        // the row's address has to state the root in both places, the way the share browser
        // always has, or the share is asked for `Comics/x y.cbz` at its top.
        let configured = SmbAddress(host: "nas.local", share: "Comics", path: "Books")
        let entry = SmbEntry(name: "x y.cbz", path: "Books/Comics/x y.cbz", isDirectory: false, length: 1)

        let publication = try #require(
            SmbContributor.publication(source: source, entry: entry, address: configured, folder: "Books/Comics")
        )
        let identity = try #require(publication.identity.normalizedPath.flatMap(URL.init(string:)))

        #expect(SmbLocator.inside(identity, of: configured) == entry.path)
        #expect(identity == SmbLocator.entry(entry.path, of: configured))
    }

    @Test("An address is inside a share only past its own name")
    func insideNeedsTheWholeName() throws {
        let configured = SmbAddress(host: "nas.local", share: "Comics", path: "Books")
        let nested = try #require(URL(string: "smb://nas.local/Comics/Books/Books/a%23b.cbz"))
        let beside = try #require(URL(string: "smb://nas.local/Comics/BooksExtra/x.cbz"))
        let elsewhere = try #require(URL(string: "smb://other.local/Comics/Books/x.cbz"))

        #expect(SmbLocator.inside(nested, of: configured) == "Books/a#b.cbz")
        #expect(SmbLocator.inside(beside, of: configured) == nil)
        #expect(SmbLocator.inside(elsewhere, of: configured) == nil)
    }

    @Test("The filename is what the row knows, and the row says so")
    func inferred() {
        let publication = row("Lantern Green 043.cbz")

        #expect(publication?.origin == .inferred)
        #expect(publication?.displayTitle == "Lantern Green 043")
        #expect(publication?.number == "43")
    }

    @Test("The folder names the series when the filename does not")
    func folderHint() {
        #expect(row("043.cbz")?.series == "Lantern Green")
    }

    @Test("A file this app cannot open is not a row")
    func unopenable() {
        #expect(row("notes.txt") == nil)
        #expect(row("cover.jpg") == nil)
        #expect(row("Lantern Green 043") == nil)
    }

    @Test("Each extension files under a format the filter can show")
    func formats() {
        #expect(row("a.cbz")?.format == .cbz)
        #expect(row("a.CBR")?.format == .cbr)
        #expect(row("a.cb7")?.format == .cb7)
        #expect(row("a.cbt")?.format == .cbt)
        #expect(row("a.epub")?.format == .epub)
        #expect(row("a.pdf")?.format == .pdf)
    }

    @Test("The walk is bounded, and the bounds are stated rather than implied")
    func bounds() {
        #expect(SmbContributor.firstSlice == 200)
        #expect(SmbContributor.maxFolders == 40)
    }

    // -- 22.1-smb-opds: the walk continues from its own frontier -------------------------

    /// A root with `count` sibling folders, each holding one file.
    private func wideTree(_ count: Int) -> [String: [SmbEntry]] {
        var tree: [String: [SmbEntry]] = [
            "": (0..<count).map { SmbEntry(name: "d\($0)", path: "d\($0)", isDirectory: true, length: 0) },
        ]
        for index in 0..<count {
            tree["d\(index)"] = [SmbEntry(name: "f.cbz", path: "d\(index)/f.cbz", isDirectory: false, length: 1)]
        }
        return tree
    }

    @Test("A continuation resumes the frontier it was handed, not the share's root")
    func continuationResumesItsOwnFrontier() async {
        // One more folder than `maxFolders` can list in a single page, so the first page is
        // proven to stop with folders still unlisted rather than finishing the share.
        let tree = wideTree(SmbContributor.maxFolders + 6)
        var listed: [String] = []
        func list(_ path: String) async throws -> [SmbEntry] { listed.append(path); return tree[path] ?? [] }

        let first = await SmbContributor.page(source: source, address: address, queue: [address.path], list: list)
        #expect(first.slice.holdsMore)
        #expect(!first.queue.isEmpty)

        listed = []
        let second = await SmbContributor.page(source: source, address: address, queue: first.queue, list: list)

        // The bug this fixes: a continuation that restarted at the root would relist "" and
        // every folder the first page already covered. Mutate the recursive call back to
        // `queue: [address.path]` and this fails, because "" and "d0" (both already listed
        // by the first page) reappear in the second page's own listing log.
        #expect(!listed.contains(""))
        #expect(!listed.contains("d0"))
        #expect(listed == first.queue)

        #expect(first.slice.publications.count + second.slice.publications.count == SmbContributor.maxFolders + 6)
        #expect(!second.slice.holdsMore)
    }

    @Test("A page's own folder budget is independent of a previous page's")
    func eachPageGetsItsOwnBudget() async {
        let tree = wideTree(SmbContributor.maxFolders * 2)
        var listings = 0
        func list(_ path: String) async throws -> [SmbEntry] { listings += 1; return tree[path] ?? [] }

        let first = await SmbContributor.page(source: source, address: address, queue: [address.path], list: list)
        #expect(listings == SmbContributor.maxFolders)

        listings = 0
        _ = await SmbContributor.page(source: source, address: address, queue: first.queue, list: list)
        #expect(listings == SmbContributor.maxFolders)
    }

    @Test("A CB7 row is refused by name, before any tap")
    func cb7Refused() {
        // Known from the name alone: no header read decides a CB7 cannot open.
        let cb7 = row("Lantern Green 043.cb7")
        #expect(cb7?.streaming == .refused)
        #expect(cb7?.isOpenable == false)

        let cbz = row("Lantern Green 043.cbz")
        #expect(cbz?.streaming == .streams)
        #expect(cbz?.isOpenable == true)
    }
}
