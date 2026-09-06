import CoreGraphics
import Foundation
import Testing

@testable import Formats

/// Cover art is protected at rest too, because a cover names a book.
///
/// The security review's rank 18 counted covers alongside downloads: the titles
/// of everything on the shelf, recoverable off a locked device. Being a cache
/// does not make the list less telling — it only makes it cheaper to lose.
///
/// Asserted on the host, which is not iOS: macOS stores and reports the same
/// attribute without enforcing it, so what this proves is that the class is
/// asked for. The enforcement is the kernel's.
@Suite("Cover protection")
struct CoverProtectionTests {

    private let directory = URL.temporaryDirectory
        .appending(path: "cover-protection-\(UUID().uuidString)", directoryHint: .isDirectory)

    /// A one-colour bitmap. The pixels are not the subject; the filing is.
    private func image() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: 8,
                height: 8,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try #require(context.makeImage())
    }

    @Test("The covers directory is created under a protection class")
    func coversDirectoryIsProtected() throws {
        let cache = CoverCache(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        cache.store(try image(), for: "urn:storyarc:1", maxPixelSize: 8)

        try expectProtection(of: directory, is: CoverCache.fileProtection)
    }

    /// The same class the downloads carry, and for the same reason: the app is
    /// woken to finish a transfer while the device is locked, and a publication
    /// indexed at that moment writes its cover here.
    @Test("Covers carry the class a locked device can still be written to under")
    func theClassMatchesTheDownloads() {
        #expect(CoverCache.fileProtection == .completeUnlessOpen)
    }
}

/// Asserts the directory carries the data-protection class the app asks for, where the platform
/// has one.
///
/// **The `#if` is the assertion on macOS, not a hole in it.** Data protection is an iOS facility;
/// on macOS the attribute is accepted and then makes every file written under it unreadable to
/// the process that wrote it, so the stores apply it on iOS only. The macOS half pins that guard
/// from both sides — deleting the `#if os(iOS)` in the store fails this on the host, and deleting
/// the store's `setAttributes` altogether fails it on a device.
///
/// **It compares against a control directory rather than asserting `nil`, because `nil` was an
/// assertion about the filesystem.** A GitHub `macos-26` runner reports
/// `completeUntilFirstUserAuthentication` on a directory nothing asked to protect, so the
/// `nil` form failed on every CI run while passing on a developer's machine. What the test
/// means to say is that the store applied *nothing of its own*, and the honest way to say that
/// is to build a directory the store never touched and require the two to agree.
func expectProtection(of directory: URL, is expected: FileProtectionType) throws {
    let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
    #if os(iOS)
    #expect(attributes[.protectionKey] as? FileProtectionType == expected)
    #else
    // A directory made the plain way, in the same volume, so it carries whatever this host
    // gives a directory nobody protected.
    let control = directory.deletingLastPathComponent()
        .appendingPathComponent("protection-control", isDirectory: true)
    try? FileManager.default.removeItem(at: control)
    try FileManager.default.createDirectory(at: control, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: control) }
    let untouched = try FileManager.default.attributesOfItem(atPath: control.path)
    // The message is one literal because `#expect`'s comment is a `Comment?`, which is
    // expressible by a string literal and not by a concatenation.
    #expect(
        attributes[.protectionKey] as? FileProtectionType
            == untouched[.protectionKey] as? FileProtectionType,
        "macOS must carry no protection class the store chose: it would make the file unreadable."
    )
    #endif
}
