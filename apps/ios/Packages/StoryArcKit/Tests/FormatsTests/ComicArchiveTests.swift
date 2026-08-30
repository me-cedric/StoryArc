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

    @Test("An entry with nothing in it is counted as skipped rather than listed as a page")
    func emptyEntriesAreCounted() async throws {
        // `publication-formats`: a damaged archive opens "whatever pages it can read and
        // states how many were skipped". The count is the stating.
        let fixture = FixtureCorpus.comic("unsupported-codec.cbz")
        let archive = try await open("unsupported-codec.cbz")

        #expect(archive.skippedPageCount == fixture.expectedSkippedPageCount)
        #expect(archive.pages.map(\.path) == fixture.expectedPageOrder)
    }

    @Test("A page in a codec nothing decodes is still a page, and is named")
    func undecodablePageIsNamed() async throws {
        // The whole of the requirement: the page stays in the list, "does not break
        // pagination", and the placeholder that stands in for it names the codec.
        // Excluding it would be the easy fix and the wrong one — a page nobody can be
        // told about is a page the reader silently loses.
        let fixture = FixtureCorpus.comic("unsupported-codec.cbz")
        let archive = try await open("unsupported-codec.cbz")

        let page = try #require(archive.pages.first { $0.path.hasSuffix(".jxl") })
        let data = try await archive.data(for: page)
        #expect(PageCodec.name(of: data, path: page.path) == fixture.expectedUndecodableCodec)
    }

    @Test("A truncated archive opens the pages that survived")
    func truncatedArchive() async throws {
        // `publication-formats` requires opening whatever can be read rather than
        // refusing the publication, and ADR-0008's own reader is what makes
        // forward-scanning recovery possible at all.
        let archive = try await open("truncated.cbz")
        let zip = try #require(archive as? ZipComicArchive)
        #expect(zip.isRecovered)

        // The fixture is 60% of a 12-page archive, so some pages survived and some
        // did not. Asserting a bound rather than an exact count: the split depends
        // on DEFLATE output, which differs between zlib builds.
        #expect(!archive.pages.isEmpty)
        #expect(archive.pages.count < 12)
        #expect(archive.pages.map(\.path).allSatisfy { $0.hasPrefix("page") })
    }

    @Test("Pages recovered from a truncated archive really decode")
    func truncatedPagesDecode() async throws {
        // An index rebuilt by scanning is worthless if the bytes behind it do not
        // come out. Every page the reader claims has to be a page.
        let archive = try await open("truncated.cbz")
        for page in archive.pages {
            let data = try await archive.data(for: page)
            #expect(
                Array(data.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
                "\(page.path) did not decode to a PNG"
            )
        }
    }

    @Test("An intact archive is not reported as recovered")
    func intactIsNotRecovered() async throws {
        let archive = try await open("natural-sort.cbz")
        let zip = try #require(archive as? ZipComicArchive)
        // Recovery trusts local headers, which ADR-0008 otherwise forbids. A
        // caller has to be able to tell the two apart.
        #expect(!zip.isRecovered)
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

    @Test("Every container StoryArc refuses is named, never reported generically")
    func refusalsAreNamed() {
        // `publication-formats` forbids a generic parse failure. Someone who
        // hands a 7-Zip comic to a comic reader deserves to be told that.
        for container in [
            FormatSniffer.Container.zip, .rar, .sevenZip, .pdf, .tar,
        ] {
            #expect(!container.displayName.isEmpty)
        }
        #expect(FormatSniffer.Container.sevenZip.displayName == "7-Zip")
    }

    @Test("A RAR with nothing behind its signature is damaged, not unsupported")
    func truncatedRarIsUnreadable() async throws {
        // RAR is readable now, so eight bytes of signature is a damaged file
        // rather than a container StoryArc declines. Naming it as unsupported
        // would tell the user to convert a file that is simply broken.
        let tmp = URL.temporaryDirectory.appending(path: "fake-\(UUID().uuidString).cbr")
        try Data([0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, 0x00]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        await #expect(throws: ComicArchiveError.unreadable) {
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
