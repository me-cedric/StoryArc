import Foundation
import Testing

@testable import Playback

/// One session, two sources, and the surfaces cannot tell which is behind them.
///
/// `audio-playback` puts it as an outcome — "the surface, the controls and the lock-screen
/// presentation are the same" — and `design.md` makes it structural: one session object,
/// two implementations, and no way for a surface to ask which. The way to assert that is
/// to run the *same* assertions over both, which is what every parameterised test below
/// does. A behaviour that needed a `switch` on the kind would fail one of the two runs.
///
/// The one place the two are allowed to differ is duration, which `design.md` calls the
/// thinnest part of the abstraction, and ``DurationTests`` is where that difference is
/// pinned rather than smoothed over.
@MainActor
struct PlaybackSessionTests {

    // MARK: - The same assertions over both sources

    @Test("Nothing is playing until a book is begun", arguments: SourceKind.allCases)
    func silentUntilBegun(_ kind: SourceKind) {
        let centre = PlayerCentre()
        #expect(!centre.isRunning)
        #expect(centre.compact == nil)
        #expect(centre.book == nil)
    }

    @Test("Beginning a book runs the session and draws a compact bar", arguments: SourceKind.allCases)
    func beginningRuns(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)

        #expect(centre.isRunning)
        #expect(centre.isPlaying)
        #expect(centre.compact?.label.title == "Bone")
        // The speed reaches the engine before the first sound does, so a publication
        // remembered at 1.5x never plays a second at 1x.
        #expect(source.calls == [.speed(1), .play])
    }

    @Test("Pause and play come from the one place", arguments: SourceKind.allCases)
    func toggling(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)

        centre.toggle()
        #expect(!centre.isPlaying)
        #expect(centre.isRunning, "a paused session still has a transport")
        centre.toggle()
        #expect(centre.isPlaying)
        #expect(source.calls == [.speed(1), .play, .pause, .play])
    }

    @Test("The chapter being played is what the bar names", arguments: SourceKind.allCases)
    func namesTheChapter(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)
        #expect(centre.compact?.label.detail == "One")

        source.advance(toPart: 1, offset: 4)
        #expect(centre.compact?.label.detail == "Two")
    }

    @Test("Ending withdraws the bar entirely", arguments: SourceKind.allCases)
    func endingWithdraws(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)
        centre.end()

        #expect(!centre.isRunning)
        #expect(centre.compact == nil, "absent, not present and empty")
        #expect(centre.book == nil)
        #expect(source.calls.last == .stop)
    }

    @Test("A source that runs out ends the session by itself", arguments: SourceKind.allCases)
    func runningOutEnds(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)
        source.runOut()

        #expect(!centre.isRunning)
        #expect(centre.compact == nil)
    }

    @Test("Speed reaches the source and is stated as a number", arguments: SourceKind.allCases)
    func speedReachesTheSource(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)

        centre.setSpeed(PlaybackSpeed(1.5))
        #expect(centre.speed.rate == 1.5)
        #expect(source.calls.contains(.speed(1.5)))
    }

    @Test("Skipping passes the configured interval to the source", arguments: SourceKind.allCases)
    func skipping(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)

        centre.skip(.back)
        centre.skip(.forward)
        #expect(source.calls.contains(.skip(.back, 15)))
        #expect(source.calls.contains(.skip(.forward, 30)))
    }

    @Test("Every part is listed in playing order, with the current one marked", arguments: SourceKind.allCases)
    func partsAreListed(_ kind: SourceKind) {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(kind)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)

        #expect(centre.parts.map(\.title) == ["One", "Two", "Three"])
        #expect(centre.currentPart?.index == 0)
        source.advance(toPart: 2, offset: 0)
        #expect(centre.currentPart?.index == 2)
    }

    // MARK: - One session at a time

    @Test("A second book stops the first, and its position is written first")
    func secondBookDisplacesTheFirst() {
        let centre = PlayerCentre()
        var log: [String] = []
        centre.onRecord = { book, place in
            log.append("record \(book.publication.displayTitle) part \(place.partIndex) at \(Int(place.offset))")
        }

        let first = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "a", title: "Bone"), source: first)
        first.advance(toPart: 1, offset: 30)

        let second = PlaybackSourceDouble(.spoken)
        centre.begin(.stub(id: "b", title: "Maus"), source: second)

        #expect(log.contains("record Bone part 1 at 30"), "the first book's place is written down")
        #expect(first.calls.last == .stop)
        #expect(centre.book?.publication.displayTitle == "Maus")
    }

    @Test("The first book is not resumed when the second ends")
    func theFirstIsNotResumed() {
        let centre = PlayerCentre()
        let first = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "a", title: "Bone"), source: first)

        let second = PlaybackSourceDouble(.spoken)
        centre.begin(.stub(id: "b", title: "Maus"), source: second)
        second.runOut()

        #expect(!centre.isRunning, "nothing is playing, rather than the first coming back")
        #expect(centre.book == nil)
        #expect(first.calls.filter { $0 == .play }.count == 1)
    }

    @Test("Opening the book that is already playing picks it up rather than restarting it")
    func openingTheSameBookAdopts() {
        #expect(SessionHandover.opening("a", whilePlaying: nil) == .none)
        #expect(SessionHandover.opening("a", whilePlaying: "a") == .adopt)
        #expect(SessionHandover.opening("b", whilePlaying: "a") == .displace)
    }
}

/// Duration, which is the one thing the two sources genuinely disagree about.
///
/// `design.md`: "a narrated file knows its duration; a synthesised voice does not", and
/// the spec is written around that — the compact bar states the chapter rather than a
/// countdown, and the scrub control is offered where a duration is known. A read-aloud
/// session shows position without a total rather than inventing one.
@MainActor
struct DurationTests {

    @Test("A narrated part reports a total, and can be scrubbed")
    func narratedHasATotal() {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)
        source.advance(toPart: 0, offset: 42)

        #expect(centre.time.elapsed == 42)
        #expect(centre.time.total == 120)
        #expect(centre.time.isScrubbable)
    }

    @Test("A synthesised voice reports position without a total, rather than inventing one")
    func spokenHasNoTotal() {
        let centre = PlayerCentre()
        let source = PlaybackSourceDouble(.spoken)
        centre.begin(.stub(id: "a", title: "Bone"), source: source)
        source.advance(toPart: 0, offset: 42)

        #expect(centre.time.elapsed == 42)
        #expect(centre.time.total == nil, "no total is invented for a voice that has none")
        #expect(!centre.time.isScrubbable, "so no scrub control is offered")
    }

    @Test("A scrub reaches the source only where a duration is known")
    func scrubbingIsRefusedWithoutADuration() {
        let centre = PlayerCentre()
        let spoken = PlaybackSourceDouble(.spoken)
        centre.begin(.stub(id: "a", title: "Bone"), source: spoken)
        centre.scrub(to: 30)
        #expect(spoken.calls == [.speed(1), .play], "nothing was sought — the control is absent, not refusing")

        let narrated = PlaybackSourceDouble(.narrated)
        centre.begin(.stub(id: "b", title: "Maus"), source: narrated)
        centre.scrub(to: 30)
        #expect(narrated.calls.contains(.seek(part: 0, offset: 30)))
    }

    @Test("Speed is clamped to the range spoken-word listeners use")
    func speedRange() {
        #expect(PlaybackSpeed(0.1).rate == 0.5)
        #expect(PlaybackSpeed(9).rate == 3)
        #expect(PlaybackSpeed(1.75).rate == 1.75)
    }
}
