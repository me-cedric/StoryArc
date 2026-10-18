import Foundation
import MediaPlayer
import Playback
import StoryArcCore
import Testing

@testable import StoryArc

/// A command centre that records what was enabled and keeps the handlers to press.
@MainActor
final class FakeRemoteCommands: RemoteCommanding {
    private(set) var enabled: [RemoteCommand: Bool] = [:]
    private(set) var handlers: [RemoteCommand: @MainActor (TimeInterval?) -> Bool] = [:]
    private(set) var targetsAdded = 0

    func setEnabled(_ on: Bool, for command: RemoteCommand) { enabled[command] = on }

    func addTarget(for command: RemoteCommand, _ handler: @escaping @MainActor (TimeInterval?) -> Bool) {
        handlers[command] = handler
        targetsAdded += 1
    }

    func removeTargets() { handlers = [:] }

    /// A press on the key, a headset or the panel.
    @discardableResult
    func press(_ command: RemoteCommand, position: TimeInterval? = nil) -> Bool {
        handlers[command]?(position) ?? false
    }

    var on: Set<RemoteCommand> { Set(enabled.filter(\.value).keys) }
}

@MainActor
final class FakeNowPlayingBoard: NowPlayingBoard {
    var info: [String: Any]?
    var isPlaying: Bool?
}

/// A narrated source with a clock and no audio: three parts of a minute each.
@MainActor
final class FakeNarratedSource: PlaybackSource {
    var moved: (@MainActor () -> Void)?
    var ended: (@MainActor () -> Void)?
    let parts: [PlaybackPart] = (0..<3).map { PlaybackPart(index: $0, title: "Part \($0 + 1)", duration: 60) }
    private(set) var place: PlaybackPlace = .start
    let skipUnit: SkipUnit = .time
    let unreadablePartCount = 0
    private(set) var isPlaying = false
    private(set) var speed: PlaybackSpeed = .normal

    func play() { isPlaying = true }
    func pause() { isPlaying = false }
    func stop() { isPlaying = false }
    func setSpeed(_ speed: PlaybackSpeed) { self.speed = speed }

    func seek(toPart index: Int, offset: TimeInterval) {
        place = PlaybackPlace(partIndex: index, offset: offset)
        moved?()
    }

    func skip(_ direction: SkipDirection, by interval: TimeInterval) {
        let offset = place.offset + (direction == .forward ? interval : -interval)
        place = PlaybackPlace(partIndex: place.partIndex, offset: max(0, min(60, offset)))
        moved?()
    }

    /// The book runs out.
    func finish() { ended?() }
}

/// The Mac's media keys and Now Playing panel over a centre of its own, with a fake command
/// centre and board. `desktop-experience`, *Media keys and system media controls*. Task 4.7.
@MainActor
@Suite("Now Playing on the Mac")
struct NowPlayingTests {
    static func book(_ id: String = "audiobook-1") -> SpokenBook {
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: "/audio/\(id).m4b"), format: .m4b,
            displayTitle: "The Long Night", authors: ["A. Narrator"], origin: .inferred
        )
        return SpokenBook(publication: publication, url: URL(filePath: "/audio/\(id).m4b"))
    }

    /// A centre with the fake platform and one book begun on a fake source.
    @MainActor
    struct Session {
        let centre = PlayerCentre()
        let commands = FakeRemoteCommands()
        let board = FakeNowPlayingBoard()
        let source = FakeNarratedSource()

        init() {
            MacPlayer.adoptPlatform(centre: centre, commands: commands, board: board)
            centre.begin(NowPlayingTests.book(), source: source)
        }
    }

    private static func start() -> Session { Session() }

    @Test("Playback starting puts the title, the chapter and the position on the panel, with the keys on")
    func entryAppears() {
        let run = Self.start()
        let (centre, commands, board, source) = (run.centre, run.commands, run.board, run.source)
        #expect(centre.isPlaying)
        #expect(board.info?[MPMediaItemPropertyTitle] as? String == "The Long Night")
        #expect(board.info?[MPMediaItemPropertyArtist] as? String == "Part 1")
        #expect(board.info?[MPMediaItemPropertyPlaybackDuration] as? TimeInterval == 60)
        #expect(board.info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval == 0)
        #expect(board.isPlaying == true)
        #expect(commands.on == Set(RemoteCommand.allCases), "a narrated book offers every command")
    }

    @Test("The keys drive the one session: pause, play, skip, the next chapter, a seek")
    func keysDriveTheSession() {
        let run = Self.start()
        let (centre, commands, board, source) = (run.centre, run.commands, run.board, run.source)
        #expect(commands.press(.pause))
        #expect(!centre.isPlaying && board.isPlaying == false)
        #expect(commands.press(.pause), "pause on a paused session still answers")
        #expect(commands.press(.play))
        #expect(centre.isPlaying)
        #expect(commands.press(.togglePlayPause))
        #expect(!centre.isPlaying)
        #expect(commands.press(.skipForward))
        #expect(source.place.offset == SkipIntervals.forward)
        #expect(commands.press(.skipBackward))
        #expect(source.place.offset == SkipIntervals.forward - SkipIntervals.back)
        #expect(commands.press(.nextTrack))
        #expect(source.place.partIndex == 1)
        #expect(board.info?[MPMediaItemPropertyArtist] as? String == "Part 2")
        #expect(commands.press(.previousTrack))
        #expect(source.place.partIndex == 0)
        #expect(commands.press(.changePosition, position: 42))
        #expect(source.place.offset == 42)
        #expect(board.info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval == 42)
        #expect(!commands.press(.changePosition, position: nil))
    }

    @Test("The entry leaves when playback ends, and when the book runs out")
    func entryLeaves() {
        let run = Self.start()
        let (centre, commands, board, source) = (run.centre, run.commands, run.board, run.source)
        centre.end()
        #expect(board.info == nil && board.isPlaying == nil)
        #expect(commands.on.isEmpty)
        #expect(!commands.press(.play), "a key after the end reaches no session")

        centre.begin(Self.book("audiobook-2"), source: FakeNarratedSource())
        #expect(board.info?[MPMediaItemPropertyTitle] as? String == "The Long Night")
        source.finish()
        #expect(board.info != nil, "the first source's end is not the second book's")
        centre.end()
        #expect(board.info == nil)
    }

    @Test("The targets are added once for the life of the platform, however many books start")
    func wiredOnce() {
        let run = Self.start()
        let (centre, commands, board, source) = (run.centre, run.commands, run.board, run.source)
        for index in 2...5 { centre.begin(Self.book("audiobook-\(index)"), source: FakeNarratedSource()) }
        #expect(commands.targetsAdded == RemoteCommand.allCases.count)
        MacPlayer.adoptPlatform(centre: centre, commands: FakeRemoteCommands(), board: FakeNowPlayingBoard())
        #expect(commands.targetsAdded == RemoteCommand.allCases.count, "a second platform is not adopted")
    }

    @Test("A voice gets sentence skip in the track buttons and no scrubber; a narrated book gets both")
    func commandsFollowTheShape() {
        #expect(MacTransportCommands.of(skipUnit: .sentence, isScrubbable: false)
            == [.play, .pause, .togglePlayPause, .previousTrack, .nextTrack])
        #expect(MacTransportCommands.of(skipUnit: .time, isScrubbable: true) == Set(RemoteCommand.allCases))
        #expect(!MacTransportCommands.of(skipUnit: .time, isScrubbable: false).contains(.changePosition))
    }

    @Test("The speed is stated as a number")
    func speedText() {
        #expect(PlayerWindow.speedText(.normal) == "1×")
        #expect(PlayerWindow.speedText(PlaybackSpeed(1.5)) == "1.5×")
        #expect(PlayerWindow.speedText(PlaybackSpeed(0.75)) == "0.75×")
    }
}
