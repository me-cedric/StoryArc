import AVFoundation
import Foundation
import Testing

@testable import Playback

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
