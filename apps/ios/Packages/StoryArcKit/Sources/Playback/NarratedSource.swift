public import Foundation

internal import AVFoundation

/// A narrated audiobook, played by `AVFoundation`.
///
/// One of the two ``PlaybackSource`` implementations, and the surfaces cannot tell it from
/// the other. Everything specific to a narrated file is here: an `AVPlayer`, the item it is
/// playing, and the swap that happens when a folder's parts cross a file boundary.
///
/// **It is deliberately thin.** The arithmetic — which chapter a file's clock is in, where a
/// skip lands, which file to load next — is ``PlaybackTimeline``'s, asserted on the host.
/// What is left here is the engine, which a unit test cannot reach anyway.
///
/// `design.md`'s decisions, each at the line that implements it:
///
/// - `AVURLAsset` + `AVPlayer`. An M4B is MPEG-4 audio and needs nothing extra.
/// - **Speed without pitch**: `AVPlayer.rate` with `audioTimePitchAlgorithm = .timeDomain`,
///   which is the spoken-word algorithm. Set on every item, because the property is the
///   *item's* and a folder makes a new one at every part boundary — the one place this
///   would silently regress into chipmunk narration.
@MainActor
public final class NarratedSource: PlaybackSource {

    public var moved: (@MainActor () -> Void)?
    public var ended: (@MainActor () -> Void)?

    public var parts: [PlaybackPart] { timeline.playbackParts }
    public private(set) var place: PlaybackPlace = .start

    /// Seconds, by ``SkipIntervals``. A narrated file has a clock.
    public let skipUnit: SkipUnit = .time

    /// `private(set)`, not `let`: task 16.5 adds a part to this count the moment its file
    /// fails mid-playback, on top of whatever ``AudiobookReader`` already found unreadable
    /// at index time. ``PlayerCentre`` re-reads it on every ``moved`` — which a decode
    /// failure fires too, since it ends in the same `load(part:offset:)` a successful skip
    /// does.
    public private(set) var unreadablePartCount: Int

    /// Set just before ``ended`` fires for a last part that could not be decoded.
    public private(set) var endedOnFailure = false

    private let timeline: PlaybackTimeline
    /// Internal, not private, so `NarratedSourceFailureTests` can post a failure for its item.
    let player = AVPlayer()
    private var speed: PlaybackSpeed = .normal

    /// The file the current item holds, which is what turns the player's clock into a place.
    private var playing: URL?
    private var ticks: Any?
    private var reachedEnd: (any NSObjectProtocol)?
    private var failedToReachEnd: (any NSObjectProtocol)?
    /// The files already counted as unreadable, so a repeated report adds nothing.
    private var failedFiles: Set<URL> = []
    /// Where the engine first reported that the current file cannot play to its end.
    ///
    /// Task 23.6, owner answer O21. The engine reports a cut from its read-ahead and then plays
    /// the item on to its nominal end through the normal end path, so ``fileFinished()`` reads
    /// this to end on the failure, here, rather than at the nominal end.
    /// ponytail: the read-ahead reports at or before the cut, never after it, so a resume can
    /// replay audio that played and cannot skip audio that did not.
    private var failedPlace: PlaybackPlace?

    public init(_ book: Audiobook) {
        timeline = PlaybackTimeline(parts: book.parts)
        unreadablePartCount = book.unreadablePartCount
        player.actionAtItemEnd = .pause
        observeTime()
    }

    // **No `deinit`.** Swift 6 will not let a nonisolated one touch this object's
    // actor-isolated state, and there is no need: `PlayerCentre.finish` calls `stop()` on
    // every path that ends a session, and `stop()` is where the observers go. A teardown
    // that only ran on deallocation would be a teardown that ran whenever ARC felt like it.

    // MARK: - The transport

    public func play() {
        if playing == nil { load(part: place.partIndex, offset: place.offset) }
        player.rate = Float(speed.rate)
    }

    public func pause() { player.pause() }

    public func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        playing = nil
        if let ticks { player.removeTimeObserver(ticks) }
        ticks = nil
        if let reachedEnd { NotificationCenter.default.removeObserver(reachedEnd) }
        reachedEnd = nil
        if let failedToReachEnd { NotificationCenter.default.removeObserver(failedToReachEnd) }
        failedToReachEnd = nil
    }

    /// Speed without pitch.
    ///
    /// `rate` is also what starts and stops an `AVPlayer`, so setting it while paused would
    /// start the audio — which is why a paused source records the number and applies it on
    /// the next play instead.
    public func setSpeed(_ speed: PlaybackSpeed) {
        self.speed = speed
        if player.rate != 0 { player.rate = Float(speed.rate) }
    }

    /// How loud, for the sleep timer's fade.
    ///
    /// The player's own volume rather than the item's: a folder audiobook swaps items at
    /// every part boundary, and a gain set on the item would jump back to full the moment a
    /// fade crossed one. Android's fade is applied to the `MediaController` for the same
    /// reason.
    public func setVolume(_ gain: Double) {
        player.volume = Float(min(1, max(0, gain)))
    }

    public func seek(toPart index: Int, offset: TimeInterval) {
        load(part: index, offset: offset)
    }

    public func skip(_ direction: SkipDirection, by interval: TimeInterval) {
        guard let landed = timeline.skip(direction, by: interval, from: place) else { return }
        load(part: landed.partIndex, offset: landed.offset)
    }

    // MARK: - The engine

    /// Puts the player on a part, loading its file first when that is a different one.
    private func load(part index: Int, offset: TimeInterval) {
        guard let target = timeline.seek(toPart: index, offset: offset) else { return }

        if playing != target.url {
            let item = AVPlayerItem(url: target.url)
            // The item's property, not the player's, so it is set on every item a folder
            // produces. A folder played at 1.5x with this forgotten would rise in pitch at
            // every part boundary and nothing in a build would say so.
            item.audioTimePitchAlgorithm = .timeDomain
            player.replaceCurrentItem(with: item)
            playing = target.url
            failedPlace = nil
            observeEnd(of: item)
        }

        player.seek(
            to: CMTime(seconds: target.fileTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        place = PlaybackPlace(partIndex: index, offset: offset)
        moved?()
    }

    /// The clock, four times a second.
    ///
    /// Often enough that a chapter change is noticed while the listener is still looking at
    /// the bar, and rare enough that the shell is not redrawn on every frame.
    private func observeTime() {
        ticks = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 4),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.clock(reached: time.seconds) }
        }
    }

    private func clock(reached seconds: TimeInterval) {
        guard let playing, seconds.isFinite else { return }
        guard let found = timeline.place(atFileTime: seconds, in: playing) else { return }
        guard found != place else { return }
        place = found
        moved?()
    }

    /// The current file ran out: the next one, or the end of the book. And the file that
    /// cannot: the same move, task 16.5 adds, with the part counted rather than silently
    /// skipped.
    private func observeEnd(of item: AVPlayerItem) {
        if let reachedEnd { NotificationCenter.default.removeObserver(reachedEnd) }
        reachedEnd = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fileFinished() }
        }
        if let failedToReachEnd { NotificationCenter.default.removeObserver(failedToReachEnd) }
        failedToReachEnd = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fileFailed() }
        }
    }

    private func fileFinished() {
        // The next part in a *different* file. A chaptered M4B has none — every part is in
        // the one file — so running that file out is running the book out.
        let next = place.partIndex + 1
        guard let target = timeline.seek(toPart: next, offset: 0), target.url != playing else {
            if let failedPlace {
                place = failedPlace
                endedOnFailure = true
                moved?()
            }
            ended?()
            return
        }
        load(part: next, offset: 0)
        player.rate = Float(speed.rate)
    }

    /// The current file could not be decoded to its end: counted, and played past.
    ///
    /// Task 16.5, `publication-formats`: a damaged audiobook "plays what it can and states
    /// how much it could not", by the same rule that opens a comic missing pages. The count
    /// goes up before the move, so a listener who stops at exactly this part still sees the
    /// damage stated. A file counts once, however often the engine says so. What happens next
    /// is ``PlaybackTimeline/response(toFailureAtPart:itemHasFailed:)``'s, on every report: a
    /// file that fails again after a seek back still hands over, and a last file whose item
    /// fails after it carried on still ends.
    private func fileFailed() {
        if let playing, failedFiles.insert(playing).inserted { unreadablePartCount += 1 }
        if failedPlace == nil { failedPlace = place }
        switch timeline.response(
            toFailureAtPart: place.partIndex,
            itemHasFailed: player.currentItem?.status == .failed
        ) {
        case .moveTo(let next):
            load(part: next, offset: 0)
            player.rate = Float(speed.rate)
        case .carryOn:
            moved?()
        case .end:
            endedOnFailure = true
            ended?()
        }
    }
}
