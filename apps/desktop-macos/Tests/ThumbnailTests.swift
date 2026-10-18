import Foundation
import Testing

@testable import StoryArc

/// The Quick Look thumbnail's cover rule and the extension the app carries. Task 5.4. Finder
/// itself, a folder of fixtures in icon view, is the owner's check: an agent session cannot see
/// Finder's icons.
@Suite("Thumbnails")
struct ThumbnailTests {
    @Test("A comic and an ebook give their cover, bounded by the size Finder asks for", arguments: [
        "natural-sort.cbz", "rar5-store.cbr", "tar-store.cbt",
    ])
    func comicCover(name: String) async throws {
        let file = TestFixtures.comics.appending(path: name)
        let cover = try #require(await ThumbnailCover.image(for: file, maxPixelSize: 256))
        #expect(max(cover.width, cover.height) <= 256)
        #expect(cover.width > 0 && cover.height > 0)
    }

    @Test("An EPUB gives its cover")
    func ebookCover() async throws {
        let file = try TestFixtures.copyEbook("fixture.epub")
        let cover = await ThumbnailCover.image(for: file, maxPixelSize: 128)
        #expect(cover != nil)
    }

    @Test("An empty, locked or refused file gives no cover, so Finder keeps its generic icon", arguments: [
        "no-pages.cbz", "password-protected.cbz", "refused.cb7",
    ])
    func noCover(name: String) async {
        #expect(await ThumbnailCover.image(for: TestFixtures.comics.appending(path: name), maxPixelSize: 256) == nil)
    }

    @Test("A damaged file, bytes that are no archive at all, gives no cover and raises nothing")
    func damaged() async throws {
        let file = URL.temporaryDirectory.appending(path: "thumbnail-damaged.cbz")
        try Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(await ThumbnailCover.image(for: file, maxPixelSize: 256) == nil)
    }

    @Test("The app carries the extension, for the comic and EPUB types, sandboxed")
    func extensionIsEmbedded() throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let appex = try #require(Bundle(url: plugins.appending(path: "StoryArcThumbnails.appex")))
        let info = try #require(appex.infoDictionary?["NSExtension"] as? [String: Any])
        #expect(info["NSExtensionPointIdentifier"] as? String == "com.apple.quicklook.thumbnail")
        let types = (info["NSExtensionAttributes"] as? [String: Any])?["QLSupportedContentTypes"] as? [String]
        let expected: Set = ["app.storyarc.cbz", "app.storyarc.cbr", "app.storyarc.cbt", "org.idpf.epub-container"]
        #expect(Set(types ?? []) == expected)
    }
}
