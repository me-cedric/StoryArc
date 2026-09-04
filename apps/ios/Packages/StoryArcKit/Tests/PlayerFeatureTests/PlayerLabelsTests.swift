import Foundation
import Testing

import Playback
@testable import PlayerFeature

/// What the player states, in words.
///
/// Every one of these is a requirement rather than a formatting preference, which is why
/// they are a value with tests rather than string interpolation inside a view body:
///
/// - `audio-playback`: a skip control states "the interval … on the control itself".
/// - `audio-playback`: the scrub control "is announced as an adjustable with its position
///   stated in time, not as a percentage".
/// - `audio-playback`: a publication with no chapter markers "lists its parts in playing
///   order instead, rather than showing an empty list".
/// - `publication-formats`: a damaged audiobook "states how much it could not" play.
@Suite("Player labels")
struct PlayerLabelsTests {

    // MARK: - Time on the face of the player

    @Test("A short position is minutes and seconds")
    func shortTime() {
        #expect(PlayerLabels.time(0) == "0:00")
        #expect(PlayerLabels.time(9) == "0:09")
        #expect(PlayerLabels.time(70) == "1:10")
        #expect(PlayerLabels.time(599) == "9:59")
    }

    /// An audiobook chapter runs past an hour often enough that `62:30` would be a real
    /// thing a listener saw.
    @Test("An hour or more gains an hours field")
    func longTime() {
        #expect(PlayerLabels.time(3600) == "1:00:00")
        #expect(PlayerLabels.time(3750) == "1:02:30")
    }

    @Test("A negative or unmeasurable time is zero rather than a minus sign")
    func brokenTime() {
        #expect(PlayerLabels.time(-5) == "0:00")
        #expect(PlayerLabels.time(.nan) == "0:00")
        #expect(PlayerLabels.time(.infinity) == "0:00")
    }

    // MARK: - Time to a screen reader

    /// `audio-playback`: the scrub control's position is stated "in time, not as a
    /// percentage". `0:09` read aloud is "zero colon zero nine", which is why the spoken
    /// form is built separately rather than reusing the face of the player.
    @Test("A screen reader hears units, never a colon")
    func spokenTime() {
        #expect(PlayerLabels.spokenTime(9) == "9 seconds")
        #expect(PlayerLabels.spokenTime(70) == "1 minute, 10 seconds")
        #expect(PlayerLabels.spokenTime(120) == "2 minutes")
        #expect(PlayerLabels.spokenTime(3750) == "1 hour, 2 minutes, 30 seconds")
    }

    @Test("Zero is spoken as a time, not as nothing")
    func spokenZero() {
        #expect(PlayerLabels.spokenTime(0) == "0 seconds")
    }

    @Test("No spoken position is ever a percentage")
    func neverAPercentage() {
        for seconds in [0.0, 1, 59, 60, 3599, 3600, 7325] {
            #expect(!PlayerLabels.spokenTime(seconds).contains("%"))
            #expect(!PlayerLabels.spokenTime(seconds).lowercased().contains("percent"))
        }
    }

    // MARK: - What a skip control says

    /// `audio-playback`: "the interval is stated on the control itself". A control that only
    /// showed an arrow would leave a listener guessing whether it moves 10 seconds or 60.
    @Test("A skip by time states its interval")
    func skipByTime() {
        let intervals = SkipIntervals(back: 15, forward: 30)
        #expect(PlayerLabels.skip(.back, unit: .time, intervals: intervals) == .time("15 seconds"))
        #expect(PlayerLabels.skip(.forward, unit: .time, intervals: intervals) == .time("30 seconds"))
    }

    /// A configured interval is what is stated, not the default.
    @Test("A configured interval is the one stated")
    func skipStatesTheConfiguredInterval() {
        let intervals = SkipIntervals(back: 5, forward: 60)
        #expect(PlayerLabels.skip(.back, unit: .time, intervals: intervals) == .time("5 seconds"))
        #expect(PlayerLabels.skip(.forward, unit: .time, intervals: intervals) == .time("1 minute"))
    }

    /// A synthesised voice has no seconds to state, and `ebook-reader` asks its controls for
    /// sentence skip by name. Same two buttons, different words.
    @Test("A skip by sentence says so instead of stating seconds")
    func skipBySentence() {
        #expect(PlayerLabels.skip(.back, unit: .sentence, intervals: .default) == .sentence)
        #expect(PlayerLabels.skip(.forward, unit: .sentence, intervals: .default) == .sentence)
    }

    // MARK: - Where there is no time to show

    /// `design.md`: a read-aloud session "shows position without a total rather than
    /// inventing one". The position it shows is which part — a real position — rather than a
    /// countdown it would have to guess at.
    @Test("A source with no duration states which part it is on")
    func positionWithoutATotal() {
        #expect(PlayerLabels.position(part: 1, of: 12, time: .unknown) == .part(index: 2, of: 12))
    }

    @Test("A source with a duration states elapsed and total")
    func positionWithATotal() {
        let time = PlaybackTime(elapsed: 70, total: 300)
        #expect(PlayerLabels.position(part: 0, of: 3, time: time) == .time(elapsed: "1:10", total: "5:00"))
    }

    /// One part is the whole book, so numbering it says nothing a listener needs.
    @Test("A single unnamed part is not numbered at the listener")
    func singlePart() {
        #expect(PlayerLabels.position(part: 0, of: 1, time: .unknown) == PositionLabel.none)
    }

    /// The case that must be unreachable: a total of zero rendered as a countdown. There is
    /// no `PositionLabel` that can carry one, which is why the absence is a case rather than
    /// a `nil` inside `.time`.
    @Test("There is no position label that states a zero total")
    func noZeroTotal() {
        let unknown = PlayerLabels.position(part: 0, of: 4, time: .unknown)
        if case .time = unknown {
            Issue.record("a source with no duration produced an elapsed-and-total label")
        }
    }

    // MARK: - The chapter list

    /// `audio-playback`: "every chapter is listed with its duration and the current one
    /// marked, and … a publication with no chapter markers lists its parts in playing order
    /// instead, rather than showing an empty list".
    @Test("An unnamed part is listed by its number, never left blank")
    func unnamedPartInTheList() {
        #expect(PlayerLabels.chapter(PlaybackPart(index: 4, title: nil, duration: 90)) == .number(5))
        #expect(PlayerLabels.chapter(PlaybackPart(index: 4, title: "", duration: 90)) == .number(5))
        let named = PlaybackPart(index: 4, title: "The Sea Room", duration: 90)
        #expect(PlayerLabels.chapter(named) == .title("The Sea Room"))
    }

    @Test("A part with no known length states no length rather than zero")
    func partWithNoLength() {
        #expect(PlayerLabels.length(of: PlaybackPart(index: 0, title: "One", duration: nil)) == nil)
        #expect(PlayerLabels.length(of: PlaybackPart(index: 0, title: "One", duration: 90)) == "1:30")
    }

    // MARK: - What the compact bar cannot draw

    /// `audio-playback`, the compact bar at the largest text size: "text the bar cannot show
    /// is announced in full by assistive technology".
    ///
    /// The bar draws one truncated line, and the title is what the tail takes — so the title
    /// is the one thing that has to be here whole. It was the one thing missing: the value
    /// announced the *chapter* and fell back to the title only when there was no chapter, so
    /// a listener on VoiceOver heard "Chapter Two" for a book whose name had been cut to
    /// "The Living Moun…" on screen and was said nowhere at all.
    @Test("The bar announces the whole title, however little of it is drawn")
    func announcesTheUntruncatedTitle() {
        let long = "The Living Mountain: A Celebration of the Cairngorm Mountains of Scotland"
        let spoken = PlayerLabels.nowPlaying(SpokenLabel(title: long, detail: "Chapter Two"))
        #expect(spoken == .titleAndChapter(title: long, chapter: "Chapter Two"))
    }

    @Test("A book with nothing under its title announces the title alone")
    func announcesTitleAlone() {
        // Never `.titleAndChapter(title:chapter: "")` — a view given an empty chapter would
        // announce the separator with nothing after it.
        #expect(PlayerLabels.nowPlaying(SpokenLabel(title: "Sea Room", detail: nil)) == .title("Sea Room"))
        #expect(PlayerLabels.nowPlaying(SpokenLabel(title: "Sea Room", detail: "")) == .title("Sea Room"))
        #expect(PlayerLabels.nowPlaying(SpokenLabel(title: "Sea Room", detail: "  ")) == .title("Sea Room"))
    }

    /// The whole point of the case that carries two: the chapter never *replaces* the title.
    ///
    /// That is what the bar did — its value was `detail ?? title`, so a book with a chapter
    /// announced the chapter alone, and the truncated title was reachable nowhere.
    @Test("A chapter is announced beside the title and never instead of it")
    func theChapterNeverReplacesTheTitle() {
        let spoken = PlayerLabels.nowPlaying(SpokenLabel(title: "Sea Room", detail: "Chapter Two"))
        guard case let .titleAndChapter(title, chapter) = spoken else {
            Issue.record("a book with a chapter lost its title from the announcement")
            return
        }
        #expect(title == "Sea Room")
        #expect(chapter == "Chapter Two")
    }
}
