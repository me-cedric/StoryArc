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

    /// Seconds, by the interval the listener configured. A narrated file has a clock.
    public let skipUnit: SkipUnit = .time

    public let unreadablePartCount: Int

    private let timeline: PlaybackTimeline
    private let player = AVPlayer()
    private var speed: PlaybackSpeed = .normal

    /// The file the current item holds, which is what turns the player's clock into a place.
    private var playing: URL?
    private var ticks: Any?
    private var reachedEnd: (any NSObjectProtocol)?

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

    /// The current file ran out: the next one, or the end of the book.
    private func observeEnd(of item: AVPlayerItem) {
        if let reachedEnd { NotificationCenter.default.removeObserver(reachedEnd) }
        reachedEnd = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fileFinished() }
        }
    }

    private func fileFinished() {
        // The next part in a *different* file. A chaptered M4B has none — every part is in
        // the one file — so running that file out is running the book out.
        let next = place.partIndex + 1
        guard let target = timeline.seek(toPart: next, offset: 0), target.url != playing else {
            ended?()
            return
        }
        load(part: next, offset: 0)
        player.rate = Float(speed.rate)
    }
}
