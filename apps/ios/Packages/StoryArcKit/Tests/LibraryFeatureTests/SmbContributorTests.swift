import Foundation
import Smb
import StoryArcCore
import Testing

@testable import LibraryFeature

/// What one file on a share looks like as a row.
///
/// A share is the one source that cannot be asked — it is a filesystem, walked. Two things
/// follow, and both are asserted here: the row is identified by its path, as a scanned file
/// is, so a share's copy and a downloaded copy fold together with no server identifier; and
/// the metadata is the filename's and says so, because reading the file's own would mean
/// fetching the archive. Android's `SmbContributorTest` makes the same claims.
struct SmbContributorTests {

    private let source = UUID()

    private func row(_ name: String, folder: String = "/comics/Lantern Green") -> Publication? {
        SmbContributor.publication(
            source: source,
            entry: SmbEntry(name: name, path: "\(folder)/\(name)", isDirectory: false, length: 1),
            folder: folder
        )
    }

    @Test("A file is identified by its path, as a scanned file is")
    func identity() {
        let publication = row("Lantern Green 043.cbz")

        #expect(
            publication?.identity.normalizedPath == "/comics/Lantern Green/Lantern Green 043.cbz"
        )
        #expect(publication?.identity.serverIdentifier == nil)
        #expect(publication?.sourceID == source)
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
