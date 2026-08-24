import Foundation
import Testing

@testable import Formats

/// Asserted against the shared corpus in `packages/test-fixtures`, using the
/// expectations recorded in its `manifest.json`. Android's `ComicArchiveTest`
/// reads the same manifest, so neither platform can privately redefine what a
/// correct parse is.
@Suite("Comic archive reading")
struct ComicArchiveTests {
    private func open(_ name: String) async throws -> any ComicArchiveReading {
        try await ComicArchiveOpener.open(fileAt: FixtureCorpus.url("comics/\(name)"))
    }

    @Test("Every fixture parses to the page order its manifest records", arguments: [
        "natural-sort.cbz",
        "nested-chapters.cbz",
        "non-image-entries.cbz",
        "mislabelled-zip.cbr",
        "single-page.cbz",
        "double-page-spread.cbz",
        "no-pages.cbz",
        "stored-entries.cbz",
        "zip64.cbz",
        "archive-comment.cbz",
        "data-descriptor.cbz",
        "tar-store.cbt",
        "tar-nested-chapters.cbt",
    ])
    func matchesManifest(name: String) async throws {
        let fixture = FixtureCorpus.comic(name)
        let archive = try await open(name)

        #expect(archive.pages.count == fixture.expectedPageCount, "\(name): \(fixture.pins)")
        #expect(archive.pages.map(\.path) == fixture.expectedPageOrder, "\(name): \(fixture.pins)")
    }

    @Test("A ZIP named .cbr opens, because format comes from content not extension")
    func formatFromContent() async throws {
        let url = FixtureCorpus.url("comics/mislabelled-zip.cbr")

        #expect(try FormatSniffer.container(ofFileAt: url) == .zip)
        #expect(try await open("mislabelled-zip.cbr").pages.count == 3)
    }

    @Test("An archive with no images reports zero pages rather than failing")
    func noPagesIsNotAnError() async throws {
        let archive = try await open("no-pages.cbz")

        #expect(archive.pages.isEmpty)
        #expect(archive.skippedPageCount == 0)
    }

    @Test("A truncated archive fails as unreadable rather than crashing or hanging")
    func truncatedArchive() async {
        // `publication-formats` wants partial recovery. ADR-0008's own reader
        // makes forward-scanning recovery possible, but it is not implemented
        // yet — so the honest behaviour today is a clean `.unreadable`, recorded
        // here so the day a recovering reader lands, this test is what changes.
        await #expect(throws: ComicArchiveError.unreadable) {
            try await open("truncated.cbz")
        }
    }

    @Test("Page bytes decode back to the PNG that was packed")
    func readsPageBytes() async throws {
        let archive = try await open("natural-sort.cbz")
        let first = try #require(archive.pages.first)

        let data = try await archive.data(for: first)

        #expect(!data.isEmpty)
        // PNG magic — proves the bytes are the page and not a header or padding.
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test("ComicInfo.xml is captured as metadata, not served as a page")
    func capturesComicInfo() async throws {
        let archive = try #require(
            try await open("non-image-entries.cbz") as? ZipComicArchive
        )

        #expect(archive.pages.map(\.path) == ["page1.png", "page2.png"])
        let info = try #require(archive.comicInfoData)
        let xml = try #require(String(data: info, encoding: .utf8))
        #expect(xml.contains("Fixture Series"))
    }

    @Test("Reading every page skips nothing in a healthy archive")
    func readsAllPages() async throws {
        let archive = try await open("natural-sort.cbz")
        let zip = try #require(archive as? ZipComicArchive)

        let readable = await zip.readableData(for: archive.pages)

        #expect(readable.count == archive.pages.count)
    }
}

@Suite("Container sniffing")
struct FormatSnifferTests {
    @Test("ZIP, RAR 4, RAR 5, 7-Zip and PDF are identified from their magic bytes")
    func signatures() {
        #expect(FormatSniffer.container(of: [0x50, 0x4B, 0x03, 0x04]) == .zip)
        #expect(FormatSniffer.container(of: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]) == .rar)
        #expect(FormatSniffer.container(of: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]) == .rar)
        #expect(FormatSniffer.container(of: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) == .sevenZip)
        #expect(FormatSniffer.container(of: [0x25, 0x50, 0x44, 0x46, 0x2D]) == .pdf)
    }

    @Test("Unrecognised bytes return nil rather than guessing")
    func unrecognised() {
        #expect(FormatSniffer.container(of: [0x00, 0x01, 0x02, 0x03]) == nil)
        #expect(FormatSniffer.container(of: []) == nil)
    }

    @Test("A RAR names its container so the user is told what they actually have")
    func rarIsNamed() async throws {
        // ADR-0005: CBR is blocked on a licence review, not on capability. The
        // error carries the container so the message can say "RAR", which is
        // more useful than a generic failure.
        let tmp = URL.temporaryDirectory.appending(path: "fake-\(UUID().uuidString).cbr")
        try Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, 0x00]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        await #expect(throws: ComicArchiveError.unsupportedContainer(.rar)) {
            try await ComicArchiveOpener.open(fileAt: tmp)
        }
    }

    @Test("Probing a remote file stays a single small read")
    func probeIsBounded() {
        // `network-share` requires opening a 400 MB archive over SMB without
        // transferring it, and sniffing is the first read. What costs money is
        // the round trip, not the byte count — 265 bytes and 8 bytes are the
        // same single SMB read, and 265 is the floor because TAR puts its magic
        // at offset 257. A whole 4 KB page would still be one round trip, so
        // this bound exists to catch a probe that starts scanning the file
        // rather than reading its head.
        #expect(FormatSniffer.probeLength <= 512)
        #expect(FormatSniffer.probeLength >= TarReader.magicOffset + 5)
    }
}
