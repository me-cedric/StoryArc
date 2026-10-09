import XCTest

/// An audiobook comes back at the part and the second it was left on, after the app is killed.
///
/// `audiobooks-and-playback` 13.3. Android was proved on 2026-09-08. This is the iOS half, on a
/// simulator: `ResumeWiringTests` read the source, and nothing ran the round trip. A start at
/// part one after the relaunch fails it. Sea Room is one M4B with three chapters of two seconds.
@MainActor
final class AudiobookResumeTests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testAnAudiobookReopensAtTheSavedPart() throws {
        let app = launch()
        try openAnAudiobook(in: app, titled: "Sea Room")
        try setSpeed("0[.,]5", in: app)
        try openTheChapterList(in: app)
        let rows = chapterRows(in: app)
        XCTAssertEqual(rows.count, 3, "Sea Room lists \(rows.count) rows: \(rows.map(\.label))")
        rows[1].tap()
        pauseWhatPlays(in: app)
        let saved = try placeInThePlayer(app)
        XCTAssertEqual(saved.part, 1, "Part two is not the one in progress before the kill: \(saved)")
        hold(2)

        app.terminate()
        app.launch()
        try openAnAudiobook(in: app, titled: "Sea Room")
        let back = try placeInThePlayer(app)

        add(XCTAttachment(string: "before the kill: \(saved); after the relaunch: \(back)"))
        // At the saved part, or past it when the second left in that part played out before the
        // pause. Never at part one, which is what a start at zero gives.
        XCTAssertGreaterThanOrEqual(
            back.part, saved.part,
            "The book reopened at part \(back.part + 1), not at part \(saved.part + 1): \(back)"
        )
        shutter(app, named: "audiobook-reopened")
        try rewindTheBook(in: app)
        try setSpeed("1×", in: app)
    }

    /// The part in progress, its row label as a screen reader hears it, and the position the player states.
    private struct Place {
        let part: Int
        let label: String
        let position: String
    }

    /// The row in progress in the chapter list, and the position the player states.
    private func placeInThePlayer(_ app: XCUIApplication) throws -> Place {
        try openTheChapterList(in: app)
        hold(1)
        let rows = chapterRows(in: app).map(\.label)
        let index = try XCTUnwrap(rows.firstIndex { $0.contains("In progress") }, "No row is in progress: \(rows)")
        app.buttons["Close"].firstMatch.tap()
        hold(1)
        let slider = app.sliders.firstMatch
        let position = slider.exists ? (slider.value as? String ?? "") : "no scrub control"
        return Place(part: index, label: rows[index], position: position)
    }
}
