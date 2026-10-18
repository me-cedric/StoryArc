import AppKit
import Formats
import Foundation
import Persistence
import Playback
import PlayerFeature
import StoryArcCore

/// The Mac's half of a playback session: the media keys and the Now Playing panel. There is
/// no `AVAudioSession` on a Mac, so nothing is claimed or given back; the interruption and
/// route rules of `audio-playback` are the system's own here.
///
/// A Mac copy of `Playback`'s `SystemPlaybackPlatform` (parent task 1.30), with its sleep-timer
/// clock: half a second at a time while a timer runs, cancelled when it is cleared or replaced.
@MainActor
final class MacPlaybackPlatform: PlaybackPlatform {
    let nowPlaying: MacNowPlaying
    private weak var centre: PlayerCentre?
    private var countdown: Task<Void, Never>?
    let output: MacAudioOutput

    init(for centre: PlayerCentre, commands: any RemoteCommanding, board: any NowPlayingBoard) {
        self.centre = centre
        nowPlaying = MacNowPlaying(publishing: centre, commands: commands, board: board)
        output = MacAudioOutput { [weak centre] in
            // `audio-playback`, *Headphones removed*: the sound would move to the speakers.
            if centre?.isPlaying == true { centre?.pause() }
        }
    }

    func sessionBegan() { output.start() }

    func published() { nowPlaying.publish() }

    func sessionEnded() {
        sleepTimerChanged(isRunning: false)
        nowPlaying.clear()
        output.stop()
    }

    func sleepTimerChanged(isRunning: Bool) {
        countdown?.cancel()
        countdown = nil
        guard isRunning else { return }
        countdown = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SleepCountdown.tick))
                guard !Task.isCancelled, let centre = self?.centre, centre.sleep != nil else { return }
                centre.tickSleepTimer(by: SleepCountdown.tick)
            }
        }
    }
}

/// Starts a narrated book on the one player and keeps its position, speed and panel wired.
///
/// A Mac copy of the iOS shell's `listen(to:at:)`, `wirePlayerRecording` and
/// `wirePlayerSpeed`. The session is `PlayerCentre.shared`, which outlives every window:
/// *The windows are hidden*, playback continues and the keys still control it. Task 4.7.
@MainActor
enum MacPlayer {
    /// The platform, made once: wiring it per session gives five handlers on every key.
    static func adoptPlatform(
        centre: PlayerCentre = .shared, commands: (any RemoteCommanding)? = nil, board: (any NowPlayingBoard)? = nil
    ) {
        guard centre.platform == nil else { return }
        centre.platform = MacPlaybackPlatform(
            for: centre, commands: commands ?? SystemRemoteCommands(), board: board ?? SystemNowPlayingBoard()
        )
    }

    /// Sends the player's positions to the store and recalls the speed, once.
    static func wire(centre: PlayerCentre = .shared, progress: ProgressStore?, library: MacLibrary?) {
        if centre.onRecord == nil {
            centre.onRecord = { reached in
                guard reached.book.publication.format.isAudio, let progress else { return }
                let record = ReadingProgress(
                    identity: reached.book.publication.identity, position: reached.position,
                    isFinished: reached.isFinished, updatedAt: Date()
                )
                Task { try? await progress.save(record) }
            }
        }
        if centre.onRecallSpeed == nil {
            let preferences = PlaybackPreferences()
            centre.onRecallSpeed = { PlaybackSpeed(preferences.speed(of: $0.id, series: $0.series)) }
            centre.onRememberSpeed = { preferences.remember($1.rate, of: $0.id, series: $0.series) }
        }
        if centre.onArtwork == nil {
            centre.onArtwork = { book in
                PlayerArtworkImage.png(
                    format: book.publication.format, cover: library?.model.cachedCover(for: book.publication)
                )
            }
        }
    }

    /// Plays a publication, or moves the session already on it. `audio-playback`: opening the
    /// book that is already playing must not restart it, and a chosen chapter starts there.
    static func listen(
        to publication: Publication, at url: URL, startingAt part: Int? = nil,
        centre: PlayerCentre = .shared, progress: ProgressStore?
    ) async {
        guard centre.handover(opening: publication.id) != .adopt else {
            if let part { centre.play(part: part) }
            return
        }
        let book = publication.format == .audioFolder
            ? await AudiobookReader.read(folderAt: url)
            : await AudiobookReader.read(fileAt: url)
        guard !book.parts.isEmpty else { return }
        adoptPlatform(centre: centre)
        centre.begin(SpokenBook(publication: publication, url: url), source: NarratedSource(book))
        if part == nil, let place = await resumePlace(of: publication, in: progress) {
            centre.play(part: place.part, offset: place.offset)
        }
        if let part { centre.play(part: part) }
    }

    /// Where a listener stopped, or `nil` for a book never listened to or finished.
    static func resumePlace(
        of publication: Publication, in progress: ProgressStore?
    ) async -> (part: Int, offset: TimeInterval)? {
        guard let progress, let stored = try? await progress.progress(for: publication.identity),
              !stored.isFinished, case let .listening(part, _, offset, _) = stored.position
        else { return nil }
        return (part, offset)
    }
}
