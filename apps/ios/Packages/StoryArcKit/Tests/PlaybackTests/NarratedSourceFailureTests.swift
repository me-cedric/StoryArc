import AVFoundation
import Foundation
import Testing

@testable import Playback
import StoryArcCore

/// What `NarratedSource` does each time the engine reports that a file failed to play to its
/// end. Task 2.5.
///
/// The test posts `AVPlayerItem.failedToPlayToEndTimeNotification` for the item the source
/// itself loaded, so the observer the source registered is the one that runs. The files do
/// not exist, which is enough: the source never reads them before the report arrives.
@MainActor
@Suite("A file that fails, and fails again")
struct NarratedSourceFailureTests {

    private static func file(_ name: String) -> URL {
        URL(fileURLWithPath: "/nonexistent/\(name)")
    }

    /// Two parts in the first file, one in the second.
    private func folder() -> NarratedSource {
        NarratedSource(Audiobook(
            parts: [
                AudiobookPart(url: Self.file("one.m4b"), title: "One", start: 0, duration: 60),
                AudiobookPart(url: Self.file("one.m4b"), title: "Two", start: 60, duration: 60),
                AudiobookPart(url: Self.file("two.m4b"), title: "Three", start: 0, duration: 60),
            ],
            unreadablePartCount: 0
        ))
    }

    private func fail(_ source: NarratedSource) async {
        NotificationCenter.default.post(
            name: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: source.player.currentItem
        )
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// Task 23.6: the end the source reports for a last file that cannot be decoded says so,
    /// before it fires, so the centre does not record the book as finished.
    @Test("A last file that cannot be decoded ends the book as a failure")
    func theLastFileFailingEndsOnFailure() async {
        let source = NarratedSource(Audiobook(
            parts: [AudiobookPart(url: Self.file("only.m4b"), title: "Only", start: 0, duration: 60)],
            unreadablePartCount: 0
        ))
        defer { source.stop() }
        var reported: Bool?
        source.ended = { [unowned source] in reported = source.endedOnFailure }
        source.seek(toPart: 0, offset: 0)
        for _ in 0..<200 where source.player.currentItem?.status != .failed {
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(source.player.currentItem?.status == .failed, "the engine never failed the missing file")

        await fail(source)

        #expect(reported == true, "the source ended without saying that its last part failed")
    }

    /// Task 23.6, owner answer O21, over the real `truncated.m4b`. The engine reports the cut
    /// from its read-ahead and then plays the item on to its nominal end through the normal
    /// end path. That end is still a damaged one: it says so, and the place goes back to where
    /// the failure was reported.
    @Test("A cut-short file that plays on to its end still ends as a failure, at the failed part")
    func aCutShortFileEndsOnFailure() async throws {
        let truncated = try #require(Self.fixture("audiobooks/truncated.m4b"), "no test-fixtures corpus")
        let source = NarratedSource(Audiobook(
            parts: [
                AudiobookPart(url: truncated, title: "One", start: 0, duration: 2),
                AudiobookPart(url: truncated, title: "Two", start: 2, duration: 2),
                AudiobookPart(url: truncated, title: "Three", start: 4, duration: 2),
            ],
            unreadablePartCount: 0
        ))
        defer { source.stop() }
        var reported: (failure: Bool, part: Int)?
        source.ended = { [unowned source] in reported = (source.endedOnFailure, source.place.partIndex) }
        source.setSpeed(PlaybackSpeed(2))
        source.play()

        for _ in 0..<600 where reported == nil {
            try await Task.sleep(for: .milliseconds(25))
        }

        let ending = try #require(reported, "the cut-short file never reached its end")
        #expect(source.unreadablePartCount == 1, "the engine never reported the cut")
        #expect(ending.failure, "a cut-short file ended as a whole book")
        #expect(ending.part == 0, "the place stayed at the nominal end, past the failed part")
    }

    /// The same ending through the session: the progress record is not finished, it holds the
    /// failed part, and the finished surface offers "Mark as finished".
    @Test("A cut-short book is recorded unfinished at the failed part, and offers the decision")
    func aCutShortBookIsRecordedUnfinished() async throws {
        let truncated = try #require(Self.fixture("audiobooks/truncated.m4b"), "no test-fixtures corpus")
        let centre = PlayerCentre()
        var records: [ReachedListening] = []
        centre.onRecord = { records.append($0) }
        centre.onRecallSpeed = { _ in PlaybackSpeed(2) }
        centre.begin(
            .stub(id: "cut-short", title: "Cut Short", format: .m4b),
            source: NarratedSource(Audiobook(
                parts: [
                    AudiobookPart(url: truncated, title: "One", start: 0, duration: 2),
                    AudiobookPart(url: truncated, title: "Two", start: 2, duration: 2),
                    AudiobookPart(url: truncated, title: "Three", start: 4, duration: 2),
                ],
                unreadablePartCount: 0
            ))
        )

        for _ in 0..<600 where !centre.hasReachedTheEnd {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(centre.hasReachedTheEnd, "the cut-short book never reached its end")
        let last = try #require(records.last)
        #expect(last.isFinished == false, "a damaged ending was recorded as a finished book")
        #expect(last.position == .listening(part: 0, partCount: 3, offset: 0, of: 2))
        #expect(centre.unreadableAtEnd == 1)
        #expect(centre.canMarkFinished, "the finished surface offers no Mark as finished")
    }

    /// The failure belongs to the file that reported it. A later whole file that plays to its
    /// end ends the book as finished, with the earlier loss still counted.
    @Test("A whole last file after a failed one ends the book as finished")
    func aWholeLastFileEndsWhole() async throws {
        let whole = try #require(Self.fixture("audiobooks/folder-parts/part1.mp3"), "no test-fixtures corpus")
        let source = NarratedSource(Audiobook(
            parts: [
                AudiobookPart(url: Self.file("one.m4b"), title: "One", start: 0, duration: 60),
                AudiobookPart(url: whole, title: "Two", start: 0, duration: 1),
            ],
            unreadablePartCount: 0
        ))
        defer { source.stop() }
        var reported: Bool?
        source.ended = { [unowned source] in reported = source.endedOnFailure }
        source.seek(toPart: 0, offset: 0)

        await fail(source)
        for _ in 0..<400 where reported == nil {
            try await Task.sleep(for: .milliseconds(25))
        }

        #expect(source.unreadablePartCount == 1)
        #expect(reported == false, "the failure of the first file was carried onto the second")
    }

    /// The corpus, found from this file. `nil` rather than a crash when it is not there.
    private static func fixture(_ path: String) -> URL? {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let url = directory.appending(path: "packages/test-fixtures/\(path)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    @Test("A file that fails again after a seek back still hands over, and counts once")
    func failingAgainStillMovesOn() async {
        let source = folder()
        defer { source.stop() }
        source.seek(toPart: 0, offset: 0)

        await fail(source)
        #expect(source.place.partIndex == 2, "the failed file did not hand over to the next one")
        #expect(source.unreadablePartCount == 1)

        source.seek(toPart: 0, offset: 0)
        await fail(source)

        #expect(
            source.place.partIndex == 2,
            "the second report of the same file was ignored, so the player stays on a file that cannot play"
        )
        #expect(source.unreadablePartCount == 1, "one file was counted twice")
    }
}
