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

    @Test("The address names the share's own root, not the configured browse root twice")
    func rootIsNotRepeated() {
        // `entry.path` already carries the walk's own root — `SmbClient.list` seeds the
        // recursion at the configured root and joins every entry against whichever folder
        // produced it — so a share configured to browse from a subfolder must not repeat
        // that subfolder in the address this builds.
        let configured = SmbAddress(host: "nas.local", share: "Comics", path: "Books")
        let entry = SmbEntry(name: "x.cbz", path: "Books/Comics/x.cbz", isDirectory: false, length: 1)

        let publication = SmbContributor.publication(
            source: source, entry: entry, address: configured, folder: "Books/Comics"
        )

        #expect(publication?.identity.normalizedPath == "smb://nas.local/Comics/Books/Comics/x.cbz")
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
}
