import Foundation
import Testing

@testable import EpubReaderFeature

/// That the reflowable reader answers a tap the way the comic reader does.
///
/// **It did not, and a reader could meet the difference.** `page-transitions` makes the
/// edge zones a setting and says that with them off "a tap anywhere toggles the chrome,
/// and no tap turns a page". The comic reader obeyed; this reader had never been told —
/// it turned on every edge tap, so a reader who switched the setting off, opened an EPUB
/// and chose Fast fade still turned pages by tapping. Its band was a quarter, too, where
/// the same requirement says "each zone is a third of the screen's width".
///
/// The two files cannot see each other — the comic reader is in another package — so this
/// suite reads the source, the way `PageCurlShaderTests` holds two shaders together.
/// `ReaderTapZonesTest` and `ReaderTapZonesTests` assert the rule itself.
@Suite("The reflowable reader's tap zones")
struct ReflowableTapZonesTests {

    private static let root: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcEpub/Tests/EpubReaderFeatureTests/this file → the root
        for _ in 0..<7 { directory.deleteLastPathComponent() }
        return directory
    }()

    private func source(_ relativePath: String) throws -> String {
        let url = Self.root.appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    private func turnSource() throws -> String {
        try source("apps/ios/Packages/StoryArcEpub/Sources/EpubReaderFeature/ReflowableTurn.swift")
    }

    @Test("The band is a third, the same third the comic reader uses")
    func aThird() throws {
        let reflowable = try turnSource()
        let comic = try source("apps/ios/Packages/StoryArcKit/Sources/ReaderFeature/ZoomablePage.swift")

        #expect(
            reflowable.contains("edgeFraction: CGFloat = 1.0 / 3.0"),
            """
            The reflowable band is not a third. It was a quarter, which left half the \
            screen doing nothing but revealing the chrome.
            """
        )
        #expect(
            comic.contains("edgeZoneFraction: CGFloat = 1.0 / 3.0"),
            "The comic reader's band moved, and this one did not follow it."
        )
    }

    @Test("A tap only turns the page while the reader's setting says it may")
    func theSettingIsHonoured() throws {
        let text = try turnSource()

        #expect(
            text.contains("if tapTurnsPages, point.x < band"),
            "The leading zone turns without consulting the setting."
        )
        #expect(
            text.contains("} else if tapTurnsPages, point.x > view.bounds.width - band {"),
            "The trailing zone turns without consulting the setting."
        )
        #expect(
            text.contains("reveal?()"),
            """
            With the zones off a tap must still reveal the chrome — the way back to the \
            menu is the one thing a reader still needs from a tap.
            """
        )
    }

    @Test("The flag reaches the gestures from the reader's own settings")
    func theFlagIsWired() throws {
        let view = try source("apps/ios/Packages/StoryArcEpub/Sources/EpubReaderFeature/EpubReaderView.swift")
        let host = try source("apps/ios/Packages/StoryArcEpub/Sources/EpubReaderFeature/EpubReaderHost.swift")

        #expect(view.contains("tapTurnsPages: settings?.turnPagesByTappingTheEdges ?? true"))
        #expect(host.contains("tapTurnsPages: tapTurnsPages"))
    }
}
