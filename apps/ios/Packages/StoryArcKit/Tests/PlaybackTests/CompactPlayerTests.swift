import Foundation
import Testing

@testable import Playback

/// The compact bar, as a value.
///
/// A tab bar cannot be unit-tested, so the rules that a later layout change would break
/// most easily are held here instead of inside a view body: what the bar says, and — the
/// one that matters — that when nothing is playing there is no value at all.
///
/// `audio-playback`'s two layout clauses, that the bar "does not displace, cover or resize
/// the navigation control" and that "the content behind it can still be scrolled to its
/// end", are the platform's own `tabViewBottomAccessory` doing its job, and neither is
/// assertable from here. The half that *is* assertable is the one that broke before: an
/// accessory whose builder returns nothing still draws an empty glass capsule and takes the
/// height, so absence has to be the shell not opening the slot — which is what ``nil``
/// below is for. `App/PlayerDock.swift` and `AppShell` carry the other half, and §6's
/// captures are its proof.
@MainActor
struct CompactPlayerTests {

    @Test("The bar names the publication and the chapter", arguments: SourceKind.allCases)
    func namesBoth(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Sea Room"), source: source)

        let bar = centre.compact
        #expect(bar?.label.title == "Sea Room")
        #expect(bar?.label.detail == "One", "the chapter, not the file")
    }

    /// The chapter is what has changed since the listener last looked, so it follows the
    /// audio rather than being read once when the book began.
    @Test("The chapter follows the audio", arguments: SourceKind.allCases)
    func chapterFollows(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Sea Room"), source: source)

        source.advance(toPart: 2, offset: 0)
        #expect(centre.compact?.label.detail == "Three")
    }

    /// `audio-playback`: when no session is active "the compact bar is absent rather than
    /// present and empty, and the space it occupied returns to the content".
    @Test("Nothing playing is no bar at all, not an empty one")
    func absentWhenSilent() {
        let centre = PlayerCentre()
        #expect(centre.compact == nil)
        #expect(!centre.isRunning, "the narrow question the shell reads to open its slot")
    }

    /// All three endings withdraw it: the listener stopped, the audio was taken for good,
    /// and the book ran out.
    @Test("Every ending withdraws the bar", arguments: SourceKind.allCases)
    func everyEndingWithdraws(_ kind: SourceKind) {
        for ending in ["listener", "lost", "ranOut"] {
            let centre = PlayerCentre()
            let source = PlaybackSourceDouble(kind)
            centre.begin(.stub(id: "a", title: "Sea Room"), source: source)

            switch ending {
            case "listener": centre.end()
            case "lost": centre.lostAudio()
            default: source.runOut()
            }
            #expect(centre.compact == nil, "\(ending) left a bar behind")
            #expect(!centre.isRunning, "\(ending) left the shell's slot open")
        }
    }

    /// A paused session keeps its bar. A listener who paused still needs the play button,
    /// and a bar that vanished on pause would be a book they could not start again.
    @Test("A paused session keeps its bar", arguments: SourceKind.allCases)
    func pausedKeepsTheBar(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Sea Room"), source: source)

        centre.toggle()
        #expect(centre.compact != nil)
        #expect(centre.compact?.isPlaying == false, "so the button shows play rather than pause")
    }

    /// The way back has to open the same bytes without asking a screen that has gone, which
    /// is why the bar carries the whole book rather than an identifier.
    @Test("The bar carries the way back to the book itself")
    func carriesTheWayBack() throws {
        let centre = PlayerCentre()
        centre.begin(.stub(id: "sea-room", title: "Sea Room"), source: PlaybackSourceDouble(.narrated))

        let bar = try #require(centre.compact)
        #expect(bar.book.url == URL(fileURLWithPath: "/sea-room"))
        #expect(bar.book.publication.displayTitle == "Sea Room")
    }

    /// Opening the book that is already playing adopts the session rather than starting a
    /// second one on it, so the way back never restarts the audio.
    @Test("The way back adopts rather than restarts")
    func thewayBackAdopts() throws {
        let centre = PlayerCentre()
        centre.begin(.stub(id: "sea-room", title: "Sea Room"), source: PlaybackSourceDouble(.narrated))

        let bar = try #require(centre.compact)
        #expect(centre.handover(opening: bar.book.id) == .adopt)
    }
}
