import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Formats
import StoryArcCore

/// The ladder, rung by rung.
///
/// `cover-art`'s *The cover ladder* orders the sources cheapest first and requires that the
/// first one to answer wins. These assert each rung in the order the ladder tries them, and
/// the two that nothing asserted before this change: a loose image beside the file, and the
/// reader's own picture above the bytes.
@Suite("The cover ladder")
struct CoverLadderTests {

    // MARK: - Rung 2, a loose image beside the file

    @Test("A cover image beside the file becomes the cover")
    func looseCoverBesideTheFile() async throws {
        let folder = try temporaryFolder()
        let book = folder.appending(path: "Book 03.m4b")
        try Data("not audio".utf8).write(to: book)
        try png(width: 40, height: 60).write(to: folder.appending(path: "cover.jpg"))

        let publication = audiobook(at: book)
        let image = await CoverLadder(overrides: store(in: folder)).cover(
            for: publication, at: book, maxPixelSize: 120
        )

        #expect(image != nil)
    }

    @Test("A poster image counts, and a cover image is preferred to it")
    func looseCoverNames() throws {
        let folder = try temporaryFolder()
        try png(width: 10, height: 15).write(to: folder.appending(path: "poster.png"))
        #expect(LooseCover.inFolder(at: folder)?.lastPathComponent == "poster.png")

        try png(width: 10, height: 15).write(to: folder.appending(path: "cover.png"))
        #expect(LooseCover.inFolder(at: folder)?.lastPathComponent == "cover.png")
    }

    @Test("A folder with no loose image answers nothing")
    func noLooseCover() throws {
        let folder = try temporaryFolder()
        try Data("x".utf8).write(to: folder.appending(path: "notes.txt"))
        #expect(LooseCover.inFolder(at: folder) == nil)
    }

    // MARK: - Rung 1, the reader's own picture

    @Test("A chosen cover is drawn instead of the one beside the file")
    func chosenCoverWins() async throws {
        let folder = try temporaryFolder()
        let book = folder.appending(path: "Book 03.m4b")
        try Data("not audio".utf8).write(to: book)
        try png(width: 40, height: 60).write(to: folder.appending(path: "cover.jpg"))

        let publication = audiobook(at: book)
        let overrides = store(in: folder)
        overrides.store(try png(width: 200, height: 300), for: publication)

        let image = try #require(
            await CoverLadder(overrides: overrides)
                .cover(for: publication, at: book, maxPixelSize: 300)
        )

        // The loose image is 40 points wide and the chosen one is 200, so the one that was
        // drawn is told from the other by its size rather than by its bytes.
        #expect(image.width > 100)
    }

    @Test("Removing a chosen cover falls back to the rung below")
    func removingFallsBack() async throws {
        let folder = try temporaryFolder()
        let book = folder.appending(path: "Book 03.m4b")
        try Data("not audio".utf8).write(to: book)
        try png(width: 40, height: 60).write(to: folder.appending(path: "cover.jpg"))

        let publication = audiobook(at: book)
        let overrides = store(in: folder)
        overrides.store(try png(width: 200, height: 300), for: publication)
        overrides.remove(for: publication)

        #expect(overrides.file(for: publication) == nil)
        let image = try #require(
            await CoverLadder(overrides: overrides)
                .cover(for: publication, at: book, maxPixelSize: 300)
        )
        #expect(image.width <= 100)
    }

    @Test("A replacement that fails to write is reported, and the earlier choice stays")
    func failedReplacementIsReported() throws {
        let folder = try temporaryFolder()
        let publication = audiobook(at: folder.appending(path: "Book 03.m4b"))
        let overrides = store(in: folder)
        let first = try png(width: 20, height: 30)
        let chosen = try #require(overrides.store(first, for: publication))
        // A folder the store cannot write into makes the replacement fail.
        let directory = chosen.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: directory.path
            )
        }

        #expect(overrides.store(try png(width: 40, height: 60), for: publication) == nil)
        #expect(overrides.data(for: publication) == first)
    }

    // MARK: - The key the override is filed under

    @Test("A chosen cover outlives a rename, because the key is the content digest")
    func chosenCoverOutlivesARename() throws {
        let folder = try temporaryFolder()
        let overrides = store(in: folder)
        let before = Publication(
            identity: PublicationIdentity(
                contentDigest: "abc123", normalizedPath: folder.appending(path: "a.m4b").path
            ),
            format: .m4b,
            displayTitle: "Before",
            origin: .inferred
        )
        let after = Publication(
            identity: PublicationIdentity(
                contentDigest: "abc123",
                normalizedPath: folder.appending(path: "somewhere/else/b.m4b").path
            ),
            format: .m4b,
            displayTitle: "After",
            origin: .inferred
        )

        overrides.store(try png(width: 20, height: 30), for: before)

        #expect(overrides.file(for: after) != nil)
        #expect(overrides.keyKind(for: after) == .contentDigest)
    }

    @Test("A publication with no digest is filed under its stable identifier, and says so")
    func noDigestFallsBackToTheStableIdentifier() throws {
        let folder = try temporaryFolder()
        let overrides = store(in: folder)
        let here = Publication(
            identity: PublicationIdentity(normalizedPath: "/pictures/Book"),
            format: .imageFolder,
            displayTitle: "Folder",
            origin: .inferred
        )
        let moved = Publication(
            identity: PublicationIdentity(normalizedPath: "/elsewhere/Book"),
            format: .imageFolder,
            displayTitle: "Folder",
            origin: .inferred
        )

        overrides.store(try png(width: 20, height: 30), for: here)

        #expect(overrides.keyKind(for: here) == .stableIdentifier)
        #expect(overrides.file(for: here) != nil)
        #expect(overrides.file(for: moved) == nil)
    }

    // MARK: - The shape a chosen picture is stored in

    @Test("A picked photograph is cropped to the cover shape")
    func pickedPictureIsCropped() throws {
        let square = try png(width: 400, height: 400)
        let shaped = try #require(CoverArtwork.coverShaped(square))
        let image = try #require(decode(shaped))

        let ratio = CGFloat(image.width) / CGFloat(image.height)
        #expect(abs(ratio - CoverArtwork.aspectRatio) < 0.01)
    }

    @Test("A photograph a phone stored on its side is turned upright first")
    func pickedPictureIsTurnedUpright() throws {
        // A phone writes a portrait photograph as a landscape bitmap plus EXIF orientation 6.
        // Upright it is 200 by 300, which is already the cover shape, so the crop keeps it
        // whole. Read without the tag it is 300 by 200, and the crop cuts it to 133 by 200.
        let sideways = try png(width: 300, height: 200, orientation: 6)
        let shaped = try #require(CoverArtwork.coverShaped(sideways))
        let image = try #require(decode(shaped))

        #expect(image.width == 200)
        #expect(image.height == 300)
    }

    @Test("A large photograph is stored bounded, never whole")
    func pickedPictureIsBounded() throws {
        let large = try png(width: 2000, height: 3000)
        let shaped = try #require(CoverArtwork.coverShaped(large))
        let image = try #require(decode(shaped))

        #expect(max(image.width, image.height) <= CoverArtwork.maxSide)
    }

    @Test("A picture larger than the ceiling is refused before it is decoded")
    func oversizedPictureIsRefused() {
        #expect(CoverArtwork.coverShaped(Data(count: CoverArtwork.maxBytes + 1)) == nil)
    }

    @Test("A picture that is not an image is refused rather than stored")
    func unreadablePictureIsRefused() {
        #expect(CoverArtwork.coverShaped(Data("not a picture".utf8)) == nil)
    }

    // MARK: - Helpers

    private func store(in folder: URL) -> CoverOverrideStore {
        CoverOverrideStore(directory: folder.appending(path: "overrides"))
    }

    private func audiobook(at url: URL) -> Publication {
        Publication(
            identity: PublicationIdentity(contentDigest: url.path, normalizedPath: url.path),
            format: .m4b,
            displayTitle: url.lastPathComponent,
            origin: .inferred
        )
    }

    private func temporaryFolder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "cover-ladder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func png(width: Int, height: Int, orientation: Int? = nil) throws -> Data {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let buffer = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(
            buffer, UTType.png.identifier as CFString, 1, nil
        ))
        let properties = orientation.map {
            [kCGImagePropertyOrientation: NSNumber(value: $0)] as CFDictionary
        }
        CGImageDestinationAddImage(destination, image, properties)
        #expect(CGImageDestinationFinalize(destination))
        return buffer as Data
    }

    private func decode(_ data: Data) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }
}
