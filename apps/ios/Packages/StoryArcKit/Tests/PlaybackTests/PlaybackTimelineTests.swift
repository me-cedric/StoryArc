import Foundation
import Testing

@testable import Playback

/// The arithmetic a narrated source does, with no engine in it.
///
/// An `AVPlayer` knows one time: how far into the *file* it is. Everything the player says
/// — which chapter, how far into it, where a skip lands — is arithmetic over the parts, and
/// arithmetic is the half that can be wrong in a way no simulator would show. So it lives
/// here as a value, and `NarratedSource` is the thin part that talks to the engine.
///
/// The two shapes are genuinely different and both are asserted below: a chaptered M4B is
/// several parts inside **one** file at increasing offsets, and a folder is one part per
/// file, each starting at zero.
@Suite("Playback timeline")
struct PlaybackTimelineTests {

    private let chaptered = PlaybackTimeline(parts: [
        AudiobookPart(url: file("book.m4b"), title: "One", start: 0, duration: 120),
        AudiobookPart(url: file("book.m4b"), title: "Two", start: 120, duration: 90),
        AudiobookPart(url: file("book.m4b"), title: "Three", start: 210, duration: 60),
    ])

    private let folder = PlaybackTimeline(parts: [
        AudiobookPart(url: file("part1.mp3"), title: nil, start: 0, duration: 60),
        AudiobookPart(url: file("part2.mp3"), title: nil, start: 0, duration: 30),
        AudiobookPart(url: file("part10.mp3"), title: nil, start: 0, duration: 45),
    ])

    // MARK: - Where the audio is

    @Test("A time inside one file finds the chapter it is in")
    func placeInAChapteredFile() {
        #expect(chaptered.place(atFileTime: 0, in: Self.file("book.m4b")) == PlaybackPlace(partIndex: 0, offset: 0))
        #expect(chaptered.place(atFileTime: 130, in: Self.file("book.m4b")) == PlaybackPlace(partIndex: 1, offset: 10))
        #expect(chaptered.place(atFileTime: 269, in: Self.file("book.m4b")) == PlaybackPlace(partIndex: 2, offset: 59))
    }

    /// The last part owns everything past its end rather than the place falling off the
    /// list: a file that runs a fraction past its final chapter marker is common, and a
    /// player that reported "no part" there would blank the chapter line at the very end of
    /// every book.
    @Test("Time past the last marker still belongs to the last chapter")
    func placePastTheEnd() {
        #expect(chaptered.place(atFileTime: 400, in: Self.file("book.m4b"))?.partIndex == 2)
    }

    @Test("Each file of a folder is its own part, starting at zero")
    func placeInAFolder() {
        #expect(folder.place(atFileTime: 12, in: Self.file("part2.mp3")) == PlaybackPlace(partIndex: 1, offset: 12))
        #expect(folder.place(atFileTime: 0, in: Self.file("part10.mp3")) == PlaybackPlace(partIndex: 2, offset: 0))
    }

    @Test("A file that is not part of this book has no place in it")
    func placeInAStranger() {
        #expect(folder.place(atFileTime: 5, in: Self.file("somewhere-else.mp3")) == nil)
    }

    // MARK: - Where a seek lands

    @Test("Seeking to a part gives the time inside its own file")
    func seekTarget() {
        let target = chaptered.seek(toPart: 1, offset: 10)
        #expect(target?.url == Self.file("book.m4b"))
        #expect(target?.fileTime == 130, "the chapter's own start plus the offset")

        let inFolder = folder.seek(toPart: 2, offset: 5)
        #expect(inFolder?.url == Self.file("part10.mp3"))
        #expect(inFolder?.fileTime == 5, "each file starts at zero")
    }

    @Test("A part that does not exist is not sought")
    func seekOffTheEnd() {
        #expect(chaptered.seek(toPart: 9, offset: 0) == nil)
    }

    // MARK: - Where a skip lands

    /// `audio-playback`: "skipping past the start or the end of a chapter continues into the
    /// neighbouring one rather than stopping at the boundary".
    @Test("Skipping back across a chapter boundary continues into the previous chapter")
    func skipBackAcrossABoundary() {
        let landed = chaptered.skip(.back, by: 30, from: PlaybackPlace(partIndex: 1, offset: 10))
        #expect(landed == PlaybackPlace(partIndex: 0, offset: 100), "20 s back into the chapter before")
    }

    @Test("Skipping forward across a chapter boundary continues into the next chapter")
    func skipForwardAcrossABoundary() {
        let landed = chaptered.skip(.forward, by: 30, from: PlaybackPlace(partIndex: 0, offset: 100))
        #expect(landed == PlaybackPlace(partIndex: 1, offset: 10))
    }

    /// A folder crosses a *file* boundary, which is the same rule and a different mechanism
    /// — the source has to load the neighbour before it can play it. The arithmetic is here;
    /// loading is `NarratedSource`'s.
    @Test("Skipping across a folder's file boundary continues into the neighbouring file")
    func skipAcrossFiles() {
        let landed = folder.skip(.forward, by: 40, from: PlaybackPlace(partIndex: 0, offset: 40))
        #expect(landed == PlaybackPlace(partIndex: 1, offset: 20))
    }

    /// Nothing before the beginning. A listener holding skip-back at the start of a book
    /// should sit at zero, not be refused and not wrap to the end.
    @Test("Skipping back from the start stops at the start")
    func skipBackFromTheStart() {
        #expect(chaptered.skip(.back, by: 60, from: .start) == .start)
    }

    @Test("Skipping forward past the end lands at the end of the last part")
    func skipForwardPastTheEnd() {
        let landed = chaptered.skip(.forward, by: 600, from: PlaybackPlace(partIndex: 2, offset: 0))
        #expect(landed?.partIndex == 2)
        #expect(landed?.offset == 60, "the last part's own length, not a time in a part that does not exist")
    }

    // MARK: - What the player is handed

    @Test("The parts a player draws carry the duration and drop the file")
    func playbackParts() {
        let parts = chaptered.playbackParts
        #expect(parts.map(\.title) == ["One", "Two", "Three"])
        #expect(parts.map(\.duration) == [120, 90, 60])
        #expect(parts.map(\.index) == [0, 1, 2])
    }

    private static func file(_ name: String) -> URL { URL(fileURLWithPath: "/books/\(name)") }
}
