import XCTest

/// Wave 6 frames: the publication page in French (25.1).
@MainActor
final class SweepWave6Tests: XCTestCase {

    override nonisolated func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 250
    }

    func testCaptureProvenanceFrench() throws {
        let app = sweepLaunch(language: "fr")
        let tab = app.tabBars.buttons.element(boundBy: 1)
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "No tab bar.")
        tab.tap()
        hold(2)
        let cover = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Harbour")).firstMatch
        XCTAssertTrue(cover.waitForExistence(timeout: 10), "No Harbour Lights cover: \(labels(in: app))")
        cover.tap()
        let line = app.staticTexts["Sur cet appareil, lisible sans réseau"]
        XCTAssertTrue(line.waitForExistence(timeout: 10), "No French line: \(labels(in: app))")
        hold(1.5)
        shutter(app, named: "provenance-fr")
    }

    // MARK: - 7.9: an EPUB resumes at its first visible element

    func testCaptureEpubResume() throws {
        let app = sweepLaunch()
        try openFixture(in: app)
        var turns = 0
        var trail: [String] = []
        while turns < 12, !(page(in: app).map { $0.chapter == 1 && $0.paragraph >= 25 } ?? false) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            hold(1.0)
            turns += 1
            trail.append(page(in: app).map { "\($0.chapter).\($0.paragraph)" } ?? "?")
        }
        let before = try XCTUnwrap(page(in: app), "No paragraph readable.")
        XCTAssertTrue(
            before.chapter == 1 && before.paragraph >= 25, "Did not reach the target: \(before) trail \(trail)"
        )
        hold(2)
        try closeReader(in: app)
        app.launch()
        try openFixture(in: app)
        hold(3)
        let after = try XCTUnwrap(page(in: app), "No paragraph after the resume.")
        XCTContext.runActivity(named: "before \(before) after \(after)") { _ in }
        shutter(app, named: "epub-resume-ch\(after.chapter)-p\(after.paragraph)")
        XCTAssertEqual(after.chapter, before.chapter)
        XCTAssertEqual(after.paragraph, before.paragraph, "The resume moved from \(before) to \(after).")
    }

    private func openFixture(in app: XCUIApplication) throws {
        try showTheShelf(in: app)
        waitForTheShelfToSettle(in: app)
        let wanted = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Fixture Publication"))
        var cover: XCUIElement?
        for _ in 0..<8 where cover == nil {
            cover = wanted.allElementsBoundByIndex.first(where: \.isHittable)
            if cover == nil { app.swipeUp() }
        }
        try XCTUnwrap(cover, "No Fixture Publication on the shelf. Copy fixture.epub into Documents/Corpus.").tap()
        let action = app.buttons.matching(opensAPublication).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 10), "No open action.")
        action.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 20), "The EPUB reader never opened.")
        hold(3)
    }

    private func closeReader(in app: XCUIApplication) throws {
        let close = app.buttons["Close"].firstMatch
        if !(close.exists && close.isHittable) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(close.waitForExistence(timeout: 5) && close.isHittable, "No Close button.")
        close.tap()
        hold(2)
    }

    private func page(in app: XCUIApplication) -> (chapter: Int, paragraph: Int)? {
        let width = app.frame.width
        let texts = app.webViews.firstMatch.staticTexts.allElementsBoundByIndex
            .filter { $0.frame.minX >= 10 && $0.frame.minX < width && $0.frame.width > 0 }
            .map(\.label)
        for text in texts {
            if let found = text.range(of: #"Chapter (\d+), paragraph (\d+)"#, options: .regularExpression) {
                let digits = CharacterSet.decimalDigits.inverted
                let nums = text[found].components(separatedBy: digits).compactMap { Int($0) }
                if nums.count == 2 { return (nums[0], nums[1]) }
            }
        }
        return nil
    }

    // MARK: - 25.7: Resume and Finish on the Home hero

    func testCaptureHomeResume() throws {
        let app = sweepLaunch(grouping: "issues", pinDownloads: false)
        try w5Tab("Home", in: app)
        let resume = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resume'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 15), "No Resume: \(labels(in: app))")
        hold(2)
        shutter(app, named: "home-resume")
    }

    // MARK: - 25.7: Continue listening, all in one process

    /// Plays Sea Room a moment, pauses, and opens its page in the same run. A folder audiobook's
    /// identity is its path in the app container, so a later run on a new container does not find
    /// the position.
    func testCaptureContinueListening() throws {
        let app = sweepLaunch(grouping: "issues", pinDownloads: false)
        try openAnAudiobook(in: app, titled: "Sea Room")
        try setSpeed("0[.,]5", in: app)
        let play = app.buttons["Play"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 10), "No Play button.")
        play.tap()
        hold(2)
        pauseWhatPlays(in: app)
        hold(3)
        try setSpeed("1×", in: app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        hold(2)
        let wanted = NSPredicate(format: "label BEGINSWITH 'Continue listening'")
        var action = app.buttons.matching(wanted).firstMatch
        for title in ["% read", "On this device"] where !action.exists {
            try showTheShelf(in: app)
            waitForTheShelfToSettle(in: app)
            let named = NSPredicate(format: "label BEGINSWITH 'Sea Room' AND label CONTAINS %@", title)
            let cover = app.buttons.matching(named)
                .allElementsBoundByIndex.first(where: \.isHittable)
            guard let cover else { continue }
            cover.tap()
            hold(2)
            action = app.buttons.matching(wanted).firstMatch
            if !action.exists { backToShelf(in: app) }
        }
        XCTAssertTrue(action.waitForExistence(timeout: 5), "No Continue listening: \(labels(in: app))")
        hold(1)
        shutter(app, named: "continue-listening")
    }

    // MARK: - 5.4 conflicts, 5.5 refusal, 5.6 background

    private static let remoteFileHint = "/tmp/w5sync/remote-file"

    func testSetupQuiet() throws {
        let app = sweepLaunch(grouping: "issues", pinDownloads: false)
        for title in ["Quiet Machines", "Tidal Reach"] {
            try w5OpenPage(of: title, in: app)
            try readFast(turns: 1, in: app)
            backToShelf(in: app)
        }
    }

    func testSyncOnly() throws {
        let app = sweepLaunch(grouping: "issues", pinDownloads: false)
        try syncNow(in: app)
    }

    func testCaptureConflictOne() throws {
        try conflictRun(titles: ["Quiet Machines.cbz"], frame: "conflict-one")
    }

    /// Run with the share folder renamed away: every sync fails, so no watermark moves.
    func testReadOffline() throws {
        let app = sweepLaunch(grouping: "issues", pinDownloads: false)
        for title in ["Quiet Machines", "Tidal Reach"] {
            try w5OpenPage(of: title, in: app)
            try readTwoAndClose(in: app)
            backToShelf(in: app)
        }
    }

    /// One process: the share is renamed away while both titles are read, so no sync settles them,
    /// then it comes back, the second device's positions are written and Sync now runs once.
    func testCaptureConflictSeveral() throws {
        let hint = try String(contentsOfFile: Self.remoteFileHint, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = URL(fileURLWithPath: hint).deletingLastPathComponent()
        let away = folder.deletingLastPathComponent().appendingPathComponent("sync.off")
        let app = sweepLaunch(grouping: "issues", pinDownloads: false)
        try showTheShelf(in: app)
        waitForTheShelfToSettle(in: app)
        hold(5)
        try FileManager.default.moveItem(at: folder, to: away)
        do {
            let counts = ((try? String(contentsOfFile: "/tmp/w5sync/turns", encoding: .utf8)) ?? "3 4")
                .split(separator: " ").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            for (title, turns) in zip(["Quiet Machines", "Tidal Reach"], counts) {
                try w5OpenPage(of: title, in: app)
                try readTwoAndClose(turns: turns, in: app)
                backToShelf(in: app)
            }
        } catch {
            try? FileManager.default.moveItem(at: away, to: folder)
            throw error
        }
        try FileManager.default.moveItem(at: away, to: folder)
        try moveRemote(titles: ["Quiet Machines.cbz", "Tidal Reach 01.cbz"])
        try w5Tab("Home", in: app)
        try syncNow(in: app)
        for _ in 0..<5 where !app.tabBars.buttons["Library"].isHittable && !app.alerts.firstMatch.exists {
            let leave = NSPredicate(format: "label IN {'Done','Close'}")
            if let done = app.buttons.matching(leave).allElementsBoundByIndex.first(where: \.isHittable) {
                done.tap()
            } else if !app.navigationBars.buttons.allElementsBoundByIndex.isEmpty {
                app.navigationBars.buttons.element(boundBy: 0).tap()
            }
            hold(1.5)
        }
        if !app.alerts.firstMatch.exists { try w5Tab("Library", in: app) }
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "No conflict notice. \(labels(in: app))")
        hold(1)
        shutter(app, named: "conflict-several")
        if let keep = alert.buttons.allElementsBoundByIndex.first(where: { $0.label.contains("Keep") }) { keep.tap() }
    }

    /// A second device moves the same titles first. This device then reads further and closes
    /// the book, which syncs: both moved since the last sync, so the notice is raised.
    private func conflictRun(titles: [String], frame: String) throws {
        let app = sweepLaunch(grouping: "issues", pinDownloads: false)
        try showTheShelf(in: app)
        waitForTheShelfToSettle(in: app)
        try moveRemote(titles: titles)
        for title in titles {
            try w5OpenPage(of: String(title.dropLast(4)).replacingOccurrences(of: " 01", with: ""), in: app)
            try readTwoAndClose(in: app)
            backToShelf(in: app)
        }
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "No conflict notice. \(labels(in: app))")
        hold(1)
        shutter(app, named: frame)
        if let keep = alert.buttons.allElementsBoundByIndex.first(where: { $0.label.contains("Keep") }) { keep.tap() }
    }

    /// Writes a position that differs from the one this device holds, as a second device would.
    private func moveRemote(titles: [String]) throws {
        let hint = try String(contentsOfFile: Self.remoteFileHint, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(fileURLWithPath: hint)
        var doc = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var library = try XCTUnwrap(doc["library"] as? [String: Any])
        var records = try XCTUnwrap(library["progress"] as? [[String: Any]])
        var touched = 0
        for index in records.indices {
            let identity = records[index]["identity"] as? [String: Any]
            let path = identity?["normalizedPath"] as? String ?? ""
            guard identity?["contentDigest"] != nil, titles.contains(where: { path.hasSuffix($0) }) else { continue }
            var position = records[index]["position"] as? [String: Any] ?? [:]
            if position["kind"] as? String == "page" { position["index"] = 0 } else { position["progression"] = 0.12 }
            records[index]["position"] = position
            records[index]["updatedAt"] = ISO8601DateFormatter().string(from: Date())
            records[index]["changedBy"] = "00000000-0000-0000-0000-00000000B0B0"
            touched += 1
        }
        XCTAssertEqual(touched, titles.count, "The sync file holds \(touched) of \(titles.count) titles.")
        library["progress"] = records
        doc["library"] = library
        try JSONSerialization.data(withJSONObject: doc).write(to: url)
    }

    private func openSync(in app: XCUIApplication) throws {
        if !app.staticTexts["Settings"].exists { try openSettings(in: app) }
        try XCTUnwrap(control("Your libraries", in: app), "No libraries row.").tap()
        hold(2)
    }

    private func syncNow(in app: XCUIApplication) throws {
        try openSync(in: app)
        let button = try XCTUnwrap(hittable("Sync now", in: app, timeout: 10), "Sync is not on.")
        button.tap()
        hold(8)
    }

    /// 5.5: the Documents folder is the library folder, and the picker offers it as On My iPhone > StoryArc.
    func testCaptureSyncFolderRefusal() throws {
        let app = sweepLaunch(grouping: "issues", pinDownloads: false)
        try openSync(in: app)
        if let off = hittable("Turn off sync", in: app, timeout: 2) { off.tap(); hold(1) }
        try XCTUnwrap(hittable("Choose a folder", in: app), "No Choose a folder.").tap()
        hold(3)
        if app.staticTexts["On My iPhone"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.175, dy: 0.275)).tap()
            hold(2)
        }
        shutter(app, named: "sync-picker-inside-storyarc")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: 0.12)).tap()
        let sentence = NSPredicate(format: "label CONTAINS 'is one of your libraries'")
        let refusal = app.staticTexts.matching(sentence).firstMatch
        let alert = app.alerts.firstMatch
        XCTAssertTrue(refusal.waitForExistence(timeout: 15) || alert.exists, "No refusal. \(labels(in: app))")
        hold(1)
        shutter(app, named: "sync-folder-refused")
    }

    /// 5.6: a refused background refresh shows grey words. The simulator refuses every request.
    func testCaptureSyncBackgroundFootnote() throws {
        let app = sweepLaunch(grouping: "issues", pinDownloads: false)
        try openSync(in: app)
        XCUIDevice.shared.press(.home)
        hold(3)
        app.activate()
        hold(3)
        let note = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'refused background'")).firstMatch
        _ = scrollTo(note, in: app)
        hold(1)
        shutter(app, named: "sync-background-footnote")
        XCTAssertTrue(note.exists, "No footnote. \(labels(in: app))")
    }

    /// 5.7: after a sync the libraries that answered still read Available, not Connecting.
    func testCaptureLibrariesAnswered() throws {
        let app = sweepLaunch(grouping: "issues", pinDownloads: false)
        try syncNow(in: app)
        let rows = app.staticTexts.matching(NSPredicate(format: "label == 'Available'")).firstMatch
        _ = scrollTo(rows, in: app, swipes: 3)
        hold(1)
        shutter(app, named: "libraries-answered")
        XCTAssertTrue(rows.exists, "No library reads Available after the sync. \(labels(in: app))")
    }

    /// Two turns, then the chrome is brought back and waited for before Close is tapped.
    private func readTwoAndClose(turns: Int = 2, in app: XCUIApplication) throws {
        let primary = try XCTUnwrap(
            app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable)
        )
        primary.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "No reader opened.")
        hold(2)
        for _ in 0..<turns {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            hold(1.2)
        }
        for _ in 0..<3 where !(app.buttons["Close"].exists && app.buttons["Close"].isHittable) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            hold(1.5)
        }
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5) && close.isHittable, "No Close button.")
        close.tap()
        hold(1.5)
    }

    // MARK: - Reader frames for preview:proof

    func testCaptureThemeAxes() throws {
        let app = sweepLaunch()
        try openFixture(in: app)
        try XCTUnwrap(revealed("Menu", in: app), "The reader revealed no menu to open.").tap()
        for _ in 0..<5 where hittableRow("Reading themes", in: app, timeout: 1) == nil {
            app.swipeUp()
            hold(0.7)
        }
        try XCTUnwrap(hittableRow("Reading themes", in: app), "The menu offers no reading-themes row.").tap()
        for _ in 0..<6 where hittableRow("Customise", in: app, timeout: 1) == nil {
            app.swipeUp()
            hold(0.5)
        }
        try XCTUnwrap(hittableRow("Customise", in: app), "The theme sheet offers no Customise.").tap()
        hold(2)
        shutter(app, named: "theme-axes")
    }

    func testCaptureComicPager() throws {
        let app = sweepLaunch(grouping: "issues", pinDownloads: false)
        try w5OpenPage(of: "Quiet Machines", in: app)
        let primary = try XCTUnwrap(
            app.buttons.matching(opensAPublication).allElementsBoundByIndex.first(where: \.isHittable)
        )
        primary.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 15), "No reader opened.")
        hold(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        hold(1.5)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        hold(1.5)
        shutter(app, named: "comic-pager")
    }

    private func labels(in app: XCUIApplication) -> String {
        "On screen: \(app.staticTexts.allElementsBoundByIndex.prefix(20).map(\.label)) "
            + "\(app.buttons.allElementsBoundByIndex.prefix(20).map(\.label))"
    }
}
