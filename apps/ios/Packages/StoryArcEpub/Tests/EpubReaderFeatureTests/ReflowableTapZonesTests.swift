import Foundation
import Testing
import UIKit

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
    func theSettingIsHonoured() {
        #expect(EdgeTap.outcome(x: 100, width: 900, tapTurnsPages: true) == false)
        #expect(EdgeTap.outcome(x: 800, width: 900, tapTurnsPages: true) == true)
        #expect(EdgeTap.outcome(x: 450, width: 900, tapTurnsPages: true) == nil)
        // With the zones off a tap must still reveal the chrome — the way back to the
        // menu is the one thing a reader still needs from a tap.
        #expect(EdgeTap.outcome(x: 100, width: 900, tapTurnsPages: false) == nil)
        #expect(EdgeTap.outcome(x: 800, width: 900, tapTurnsPages: false) == nil)
    }

    @Test("The flag reaches the gestures from the reader's own settings")
    func theFlagIsWired() throws {
        let view = try source("apps/ios/Packages/StoryArcEpub/Sources/EpubReaderFeature/EpubReaderView.swift")
        let host = try source("apps/ios/Packages/StoryArcEpub/Sources/EpubReaderFeature/EpubReaderHost.swift")

        #expect(view.contains("tapTurnsPages: settings?.turnPagesByTappingTheEdges ?? true"))
        #expect(host.contains("tapTurnsPages: tapTurnsPages"))
    }

    @Test("A tap turns the page in every mode, not only while Fast fade owns the turn")
    @MainActor
    func theTapTurnsInEveryMode() {
        var turns: [String] = []
        let gestures = TurnGestures()

        // Slide or Scroll: Fast fade does not own the turn, so Readium's animated turn
        // answers an edge tap. Before this, nothing did, and the tap only toggled the chrome.
        gestures.apply(
            turn: nil,
            animatedTurn: { turns.append("animated \($0)") },
            reveal: { turns.append("reveal") },
            tapTurnsPages: true,
            on: UIView()
        )
        gestures.tapped(at: 800, width: 900)
        gestures.tapped(at: 100, width: 900)
        gestures.tapped(at: 450, width: 900)
        #expect(turns == ["animated true", "animated false", "reveal"])

        // Fast fade: its own turn wins over Readium's.
        turns = []
        gestures.apply(
            turn: { turns.append("fade \($0)") },
            animatedTurn: { turns.append("animated \($0)") },
            reveal: { turns.append("reveal") },
            tapTurnsPages: true,
            on: UIView()
        )
        gestures.tapped(at: 800, width: 900)
        #expect(turns == ["fade true"])
    }

    /// Task 9.12: the band mirrors under right-to-left, the way the comic reader's own
    /// display order mirrors its edge taps for free. This reader has no display-order
    /// layer of its own — Readium paginates the text — so `EdgeTap` mirrors explicitly.
    @Test("Under right-to-left, the edge band turns the opposite way")
    func rightToLeftMirrorsTheBand() {
        #expect(EdgeTap.outcome(x: 100, width: 900, tapTurnsPages: true, isRightToLeft: true) == true)
        #expect(EdgeTap.outcome(x: 800, width: 900, tapTurnsPages: true, isRightToLeft: true) == false)
        #expect(EdgeTap.outcome(x: 450, width: 900, tapTurnsPages: true, isRightToLeft: true) == nil)
    }

    @Test("A tap mirrors the same way through the gestures, under right-to-left")
    @MainActor
    func theTapMirrorsThroughTheGestures() {
        var turns: [String] = []
        let gestures = TurnGestures()
        gestures.apply(
            turn: nil,
            animatedTurn: { turns.append("animated \($0)") },
            reveal: { turns.append("reveal") },
            tapTurnsPages: true,
            isRightToLeft: true,
            on: UIView()
        )
        gestures.tapped(at: 800, width: 900)
        gestures.tapped(at: 100, width: 900)
        #expect(turns == ["animated false", "animated true"])
    }

    @Test("A turn key takes the same turn a tap does, and Return reveals the chrome")
    @MainActor
    func theKeysTakeTheSameTurn() {
        var turns: [String] = []
        let gestures = TurnGestures()
        gestures.apply(
            turn: nil,
            animatedTurn: { turns.append("animated \($0)") },
            reveal: { turns.append("reveal") },
            tapTurnsPages: false,
            on: UIView()
        )

        // The tap-zone setting governs taps only: `page-transitions` keeps every other
        // trigger turning pages with the zones off.
        gestures.pressed(.forward)
        gestures.pressed(.backward)
        gestures.pressed(.toggleChrome)
        #expect(turns == ["animated true", "animated false", "reveal"])
    }

    @Test("Readium's own tap and key observers are what the reader listens to")
    func theObserversAreRegistered() throws {
        let host = try source("apps/ios/Packages/StoryArcEpub/Sources/EpubReaderFeature/EpubReaderHost.swift")
        let text = try turnSource()

        // A UIKit tap recogniser over the web view heard a tap on a link too, so following
        // a link near the edge also turned the page. Readium's observer leaves those out.
        #expect(host.contains("context.coordinator.observe(navigator)"))
        #expect(host.contains("coordinator.stopObserving(controller)"))
        #expect(text.contains("navigator.addObserver(.activate {"))
        #expect(text.contains("navigator.addObserver(.key {"))
        #expect(!text.contains("UITapGestureRecognizer"))
    }
}
