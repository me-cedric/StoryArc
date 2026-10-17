import AppKit
import Foundation
import MediaPlayer
import Playback

/// The remote commands a Mac's media keys, a headset and the system's Now Playing panel send.
enum RemoteCommand: CaseIterable, Sendable {
    case play, pause, togglePlayPause, skipBackward, skipForward, previousTrack, nextTrack, changePosition
}

/// The system's command centre, as the Mac's Now Playing talks to it. `MPRemoteCommandCenter`
/// in the app, a fake in the tests.
@MainActor
protocol RemoteCommanding: AnyObject {
    func setEnabled(_ on: Bool, for command: RemoteCommand)
    /// Points a command at the session. The position is set for `changePosition` alone.
    func addTarget(for command: RemoteCommand, _ handler: @escaping @MainActor (TimeInterval?) -> Bool)
    func removeTargets()
}

/// The system's Now Playing board. `MPNowPlayingInfoCenter` in the app, a fake in the tests.
@MainActor
protocol NowPlayingBoard: AnyObject {
    var info: [String: Any]? { get set }
    var isPlaying: Bool? { get set }
}

/// What the Mac's media keys reach, and what the system's Now Playing panel says.
///
/// A Mac copy of `Playback`'s `NowPlaying`, whose body sits inside `#if os(iOS)` (parent
/// task 1.30 splits the guard): `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` exist on
/// macOS and give the keyboard's media keys, a headset and the menu bar's Now Playing panel.
/// `desktop-experience`, *Media keys and system media controls*: the entry carries the title,
/// the chapter, the cover and the position, a seek in it moves the playback, and it leaves
/// when playback ends. The buttons are wired once for the life of the object; which are on
/// follows the source's shape (`TransportCommands`), never which source it is. Task 4.7.
@MainActor
final class MacNowPlaying {
    private weak var centre: PlayerCentre?
    private let commands: any RemoteCommanding
    private let board: any NowPlayingBoard
    private var isWired = false
    private var artwork: (bookID: String, image: MPMediaItemArtwork)?

    init(publishing centre: PlayerCentre, commands: any RemoteCommanding, board: any NowPlayingBoard) {
        self.centre = centre
        self.commands = commands
        self.board = board
    }

    /// Puts what is playing in the system's panel.
    func publish() {
        guard let centre, let label = centre.book?.label else { return }
        wire()
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: label.title,
            MPNowPlayingInfoPropertyPlaybackRate: centre.isPlaying ? centre.speed.rate : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: centre.time.elapsed,
        ]
        if let detail = label.detail { info[MPMediaItemPropertyArtist] = detail }
        // Only when it is known: a zero duration draws a scrubber pinned at the end.
        if let total = centre.time.total { info[MPMediaItemPropertyPlaybackDuration] = total }
        if let art = art(for: centre) { info[MPMediaItemPropertyArtwork] = art }
        board.info = info
        board.isPlaying = centre.isPlaying
    }

    /// Takes the book off the panel when the session ends, and turns the buttons off.
    func clear() {
        artwork = nil
        board.info = nil
        board.isPlaying = nil
        for command in RemoteCommand.allCases { commands.setEnabled(false, for: command) }
    }

    private func art(for centre: PlayerCentre) -> MPMediaItemArtwork? {
        guard let book = centre.book else { return nil }
        if let artwork, artwork.bookID == book.id { return artwork.image }
        guard let data = centre.onArtwork?(book), let image = NSImage(data: data) else { return nil }
        let art = Self.artwork(image)
        artwork = (book.id, art)
        return art
    }

    /// Off this object's isolation: the system asks for the picture on its own queue.
    nonisolated private static func artwork(_ image: NSImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func wire() {
        guard let centre else { return }
        let offered = MacTransportCommands.of(skipUnit: centre.skipUnit, isScrubbable: centre.time.isScrubbable)
        for command in RemoteCommand.allCases { commands.setEnabled(offered.contains(command), for: command) }
        guard !isWired else { return }
        isWired = true
        addTargets()
    }

    private func addTargets() {
        commands.addTarget(for: .play) { [weak self] _ in
            guard let centre = self?.centre, centre.isRunning, !centre.isPlaying else { return false }
            centre.toggle()
            return true
        }
        commands.addTarget(for: .pause) { [weak self] _ in
            guard let centre = self?.centre, centre.isRunning else { return false }
            centre.pause()
            return true
        }
        commands.addTarget(for: .togglePlayPause) { [weak self] _ in
            guard let centre = self?.centre, centre.isRunning else { return false }
            centre.toggle()
            return true
        }
        for (command, direction) in [(RemoteCommand.skipBackward, SkipDirection.back), (.skipForward, .forward)] {
            commands.addTarget(for: command) { [weak self] _ in
                guard let centre = self?.centre else { return false }
                centre.skip(direction)
                return true
            }
        }
        for (command, direction) in [(RemoteCommand.previousTrack, SkipDirection.back), (.nextTrack, .forward)] {
            commands.addTarget(for: command) { [weak self] _ in
                guard let centre = self?.centre else { return false }
                Self.moveTrack(direction, in: centre)
                return true
            }
        }
        commands.addTarget(for: .changePosition) { [weak self] position in
            guard let centre = self?.centre, let position else { return false }
            centre.scrub(to: position)
            return true
        }
    }

    /// The chapter move for a narrated book, the sentence move for a voice.
    static func moveTrack(_ direction: SkipDirection, in centre: PlayerCentre) {
        guard centre.skipUnit == .time else { return centre.skip(direction) }
        let index = centre.place.partIndex + (direction == .forward ? 1 : -1)
        guard centre.parts.indices.contains(index) else { return }
        centre.play(part: index)
    }
}

/// Which remote commands a session of this shape turns on: `Playback`'s `TransportCommands`,
/// as a set. A source measured in seconds gets skip and a scrubber; a voice gets the track
/// buttons for its sentences and no scrubber. Every source gets play, pause and the toggle.
enum MacTransportCommands {
    static func of(skipUnit: SkipUnit, isScrubbable: Bool) -> Set<RemoteCommand> {
        var offered: Set<RemoteCommand> = [.play, .pause, .togglePlayPause, .previousTrack, .nextTrack]
        if skipUnit == .time { offered.formUnion([.skipBackward, .skipForward]) }
        if isScrubbable { offered.insert(.changePosition) }
        return offered
    }
}

/// The real command centre.
@MainActor
final class SystemRemoteCommands: RemoteCommanding {
    private let centre = MPRemoteCommandCenter.shared()

    init() {
        centre.skipBackwardCommand.preferredIntervals = [NSNumber(value: SkipIntervals.back)]
        centre.skipForwardCommand.preferredIntervals = [NSNumber(value: SkipIntervals.forward)]
    }

    private func command(_ command: RemoteCommand) -> MPRemoteCommand {
        switch command {
        case .play: centre.playCommand
        case .pause: centre.pauseCommand
        case .togglePlayPause: centre.togglePlayPauseCommand
        case .skipBackward: centre.skipBackwardCommand
        case .skipForward: centre.skipForwardCommand
        case .previousTrack: centre.previousTrackCommand
        case .nextTrack: centre.nextTrackCommand
        case .changePosition: centre.changePlaybackPositionCommand
        }
    }

    func setEnabled(_ on: Bool, for command: RemoteCommand) { self.command(command).isEnabled = on }

    func addTarget(for command: RemoteCommand, _ handler: @escaping @MainActor (TimeInterval?) -> Bool) {
        self.command(command).addTarget { event in
            let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime
            return MainActor.assumeIsolated { handler(position) } ? .success : .commandFailed
        }
    }

    func removeTargets() {
        for command in RemoteCommand.allCases { self.command(command).removeTarget(nil) }
    }
}

/// The real board.
@MainActor
final class SystemNowPlayingBoard: NowPlayingBoard {
    private let board = MPNowPlayingInfoCenter.default()

    var info: [String: Any]? {
        get { board.nowPlayingInfo }
        set { board.nowPlayingInfo = newValue }
    }

    var isPlaying: Bool? {
        get { board.playbackState == .playing ? true : board.playbackState == .paused ? false : nil }
        set { board.playbackState = newValue.map { $0 ? .playing : .paused } ?? .stopped }
    }
}
