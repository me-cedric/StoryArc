import Foundation
import Testing

/// That an audiobook opens where the listener left it.
///
/// **The position was written for as long as the player existed and nothing read it back.**
/// `listen(to:at:startingAt:)` called `PlayerCentre.begin` and never seeked.
/// `NarratedSource.place` starts at `.start` and moves only from `clock(reached:)`, a periodic
/// observer that follows the audio as it plays. So every audiobook began at zero, however far
/// into it a listener was, while `wirePlayerRecording()` went on recording the place they had
/// reached. `reading-progress` asks that place to survive the app closing "exactly as a page
/// index does". It survived and was never used. Android had resumed the whole time.
///
/// **This reads source text, and that is a second choice**, for the reason
/// ``ShellWiringTests`` records at length: `apps/ios/project.yml` declares `StoryArcUITests`
/// and no app unit-test target, so nothing in this package can call `listen` and watch what it
/// does. Driving `play(part:offset:)` for real needs a `NarratedSource` over real audio and an
/// `AVPlayer`, which this host suite has no simulator for, so the offset is pinned as text
/// here too. A device walk is what would prove a book resumed; section 13.3 of the audiobook
/// change asks for exactly that.
///
/// It is a tripwire, not a proof. It asserts a call is written, never that a book resumed.
@Suite("Resume wiring")
struct ResumeWiringTests {

    /// `apps/ios`, from this file rather than the working directory: this repository nests
    /// worktrees at `.claude/worktrees/<name>/`, and a walk that climbs out validates the
    /// parent checkout instead of the one under test.
    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/apps/ios/Packages/StoryArcKit/Tests/StoryArcCoreTests/this file → apps/ios
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory
    }()

    private func source(_ relativePath: String) throws -> String {
        let url = Self.appleRoot.appendingPathComponent(relativePath)
        return try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
    }

    @Test("Opening an audiobook with no chapter chosen seeks to the recorded place")
    func resumesWhenNothingWasChosen() throws {
        let actions = try source("App/StoryArcAppActions.swift")

        #expect(
            actions.contains("if part == nil, let place = await resumePlace(of: publication)"),
            "listen() no longer resumes when the listener chose no chapter"
        )
        #expect(
            actions.contains("centre.play(part: place.part, offset: place.offset)"),
            "the recorded place is read and not seeked to"
        )
    }

    @Test("The recorded place is read from a listening position and from nothing else")
    func onlyAListeningPositionResumes() throws {
        let actions = try source("App/StoryArcAppActions.swift")

        #expect(
            actions.contains("case let .listening(part, _, offset, _) = stored?.position"),
            "a page or a reflowable position must not be read as a part index"
        )
    }

    @Test("A chosen chapter still wins over the recorded place")
    func aChosenChapterWins() throws {
        let actions = try source("App/StoryArcAppActions.swift")

        // `audio-playback`: a chosen chapter starts "at that chapter rather than where the
        // book was left". The resume is guarded on `part == nil`, so the two cannot both fire.
        #expect(
            actions.contains("if part == nil,"),
            "the resume is no longer guarded on the listener having chosen nothing"
        )
    }

    @Test("The seek carries an offset, so a resume is not rounded to the chapter")
    func theSeekCarriesAnOffset() throws {
        let centre = try source("Packages/StoryArcKit/Sources/Playback/PlayerCentre.swift")

        #expect(
            centre.contains("public func play(part index: Int, offset: TimeInterval = 0)"),
            "play(part:) no longer takes an offset, so a resume lands at the chapter's start"
        )
        #expect(
            centre.contains("source.seek(toPart: index, offset: max(0, offset))"),
            "the offset is not passed through to the source"
        )
    }
}
