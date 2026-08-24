import Foundation
import Testing

@testable import Formats

/// A plain folder has no container to parse, so its fixtures are built in a
/// temporary directory rather than committed — there would be nothing to pin.
/// What is asserted is that a folder behaves exactly like an archive: same page
/// filter, same natural sort, same skipped count. Android's
/// `ImageFolderArchiveTest` asserts the same list.
@Suite("Image folder reading")
struct ImageFolderArchiveTests {
    /// A 2x3 PNG, the same shape every committed fixture page uses.
    private static let png: [UInt8] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x03,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x8D, 0x6F, 0x26,
        0xD5, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
        0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
        0x44, 0xAE, 0x42, 0x60, 0x82,
    ]

    /// Builds a folder and hands it to `body`, cleaning up afterwards.
    private func folder(
        _ files: [String: [UInt8]],
        _ body: (URL) async throws -> Void
    ) async throws {
        let root = URL.temporaryDirectory.appending(path: "folder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, bytes) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data(bytes).write(to: url)
        }
        try await body(root)
    }

    @Test("Pages sort naturally, so page10 follows page9")
    func naturalSort() async throws {
        let files = Dictionary(
            uniqueKeysWithValues: (1...12).map { ("page\($0).png", Self.png) }
        )
        try await folder(files) { root in
            let archive = try ImageFolderArchive(directory: root)
            #expect(archive.pages.map(\.path) == (1...12).map { "page\($0).png" })
        }
    }

    @Test("Chapter subdirectories order by full path, so ch10 follows ch2")
    func nestedChapters() async throws {
        try await folder([
            "ch1/p1.png": Self.png, "ch1/p2.png": Self.png, "ch1/p10.png": Self.png,
            "ch2/p1.png": Self.png, "ch10/p1.png": Self.png,
        ]) { root in
            let archive = try ImageFolderArchive(directory: root)
            #expect(archive.pages.map(\.path) == [
                "ch1/p1.png", "ch1/p2.png", "ch1/p10.png", "ch2/p1.png", "ch10/p1.png",
            ])
        }
    }

    @Test("Non-image files are excluded and ComicInfo.xml is picked up")
    func nonImageEntries() async throws {
        let comicInfo = Array("<ComicInfo><Series>Folder</Series></ComicInfo>".utf8)
        try await folder([
            "page1.png": Self.png,
            "ComicInfo.xml": comicInfo,
            "notes.txt": Array("not a page".utf8),
            "Thumbs.db": [0, 0, 0, 0],
            "__MACOSX/._page1.png": Array("resource fork".utf8),
        ]) { root in
            let archive = try ImageFolderArchive(directory: root)
            #expect(archive.pages.map(\.path) == ["page1.png"])
            #expect(archive.comicInfoData == Data(comicInfo))
        }
    }

    @Test("A zero-length image counts as skipped rather than as a page")
    func zeroLengthIsSkipped() async throws {
        try await folder(["page1.png": Self.png, "page2.png": []]) { root in
            let archive = try ImageFolderArchive(directory: root)
            #expect(archive.pages.map(\.path) == ["page1.png"])
            #expect(archive.skippedPageCount == 1)
        }
    }

    @Test("A page's bytes come back verbatim")
    func dataRoundTrips() async throws {
        try await folder(["page1.png": Self.png]) { root in
            let archive = try ImageFolderArchive(directory: root)
            let page = try #require(archive.pages.first)
            #expect(try await archive.data(for: page) == Data(Self.png))
        }
    }

    @Test("A folder opens through the same opener as a file")
    func opensThroughTheOpener() async throws {
        try await folder(["page1.png": Self.png, "page2.png": Self.png]) { root in
            let archive = try await ComicArchiveOpener.open(fileAt: root)
            #expect(archive.pages.count == 2)
            #expect(archive is ImageFolderArchive)
        }
    }

    @Test("An empty folder reports zero pages rather than failing")
    func emptyFolder() async throws {
        try await folder([:]) { root in
            let archive = try ImageFolderArchive(directory: root)
            #expect(archive.pages.isEmpty)
            #expect(archive.skippedPageCount == 0)
        }
    }

    @Test("A path that is not a directory is refused")
    func notADirectory() async throws {
        try await folder(["page1.png": Self.png]) { root in
            #expect(throws: ComicArchiveError.unrecognisedContainer) {
                _ = try ImageFolderArchive(directory: root.appending(path: "page1.png"))
            }
        }
    }

    @Test("A symlink is not followed, so a folder cannot reach outside itself")
    func symlinksAreNotFollowed() async throws {
        let secret = URL.temporaryDirectory.appending(path: "secret-\(UUID().uuidString).png")
        try Data(Self.png).write(to: secret)
        defer { try? FileManager.default.removeItem(at: secret) }

        try await folder(["page1.png": Self.png]) { root in
            try FileManager.default.createSymbolicLink(
                at: root.appending(path: "page2.png"), withDestinationURL: secret
            )
            let archive = try ImageFolderArchive(directory: root)
            // The link would otherwise read a file outside the publication. A
            // folder is chosen by the user, but it is still untrusted input.
            #expect(archive.pages.map(\.path) == ["page1.png"])
        }
    }
}
