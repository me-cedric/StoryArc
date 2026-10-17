import Testing

@testable import StoryArc

/// Task 3.12: what a quit asks when a download is on its way, and what it does with the answer.
@MainActor
@Suite("Quitting during a download")
struct DownloadsQuitTests {
    @Test("Nothing transferring: the quit asks nothing and pauses nothing")
    func nothingTransferring() {
        var asked = false
        var paused = false
        let quit = MacQuit(
            isTransferring: false, confirm: { asked = true; return true }, pauseForQuit: { paused = true }
        )
        #expect(quit.shouldQuit())
        #expect(!asked && !paused)
    }

    @Test("A transfer, and the reader cancels: the app stays and the download runs on")
    func readerCancels() {
        var paused = false
        let quit = MacQuit(isTransferring: true, confirm: { false }, pauseForQuit: { paused = true })
        #expect(!quit.shouldQuit())
        #expect(!paused)
    }

    @Test("A transfer, and the reader agrees: it pauses for the next launch, then the app quits")
    func readerAgrees() {
        var paused = false
        let quit = MacQuit(isTransferring: true, confirm: { true }, pauseForQuit: { paused = true })
        #expect(quit.shouldQuit())
        #expect(paused)
    }

    @Test("The question says the download pauses and resumes, in the four languages")
    func words() {
        for key in ["desktop.quit.download.title", "desktop.quit.download.body", "desktop.quit.download.quit"] {
            #expect(Wave3Keys.all.contains(key), "\(key) is not held by the localization test")
        }
    }
}
