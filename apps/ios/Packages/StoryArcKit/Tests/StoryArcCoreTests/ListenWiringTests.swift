import Foundation
import Testing

/// The listen wire, pinned where nothing else reads it.
///
/// A publication page registered without `onListen:` compiles, draws, and then refuses to
/// play — so `audio-playback`'s "every control the player offers works, or is absent" fails
/// on whichever surface was missed, and only on that one. `PublicationPaneTests` reads
/// `LibraryPanes.swift` and `LibraryView.swift`; the six registrations and four hand-offs
/// below had no assertion of any kind.
///
/// The mechanism is `ShellWiringTests`' and `ResumeWiringTests`': read the source, assert
/// the literal, name the path it looked at. It cannot see a view hierarchy and does not try
/// to. It sees a wire removed.
@Suite("The listen wire")
struct ListenWiringTests {

    /// `apps/ios`, so one suite can read the package and the app target it ships in.
    private static let appleRoot: URL = {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { directory.deleteLastPathComponent() }
        return directory
    }()

    private static let registration = ".publicationPages(in: model, onOpen: onOpen, onListen: onListen)"

    private func lines(of relativePath: String) throws -> [String] {
        let url = Self.appleRoot.appendingPathComponent(relativePath)
        let text = try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has it moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("//") }
    }

    /// The counts are the branches each file draws, and `LibrarySidebar`'s four are the four
    /// of its five navigation stacks that lead to a cover. The fifth is `ReadingListDetail`,
    /// which is not a cover surface and says so in that file.
    @Test(
        "Every surface that shows a publication page hands it the way to listen",
        arguments: [
            ("Packages/StoryArcKit/Sources/LibraryFeature/HomeScreen.swift", 1),
            ("Packages/StoryArcKit/Sources/LibraryFeature/LibrarySidebar.swift", 4),
            ("App/DownloadsDestination.swift", 1),
        ]
    )
    func everySurfaceRegistersThePage(path: String, expected: Int) throws {
        let found = try lines(of: path).filter { $0.hasPrefix(Self.registration) }.count

        #expect(
            found == expected,
            """
            \(path) registers the publication page \(found) time(s), and \(expected) were \
            expected. A branch that draws covers and registers no page cannot open one; a \
            page registered without onListen: draws an audiobook it cannot play. If a \
            branch was added, give it the same registration and raise the number here.
            """
        )
    }

    @Test("The shell hands every surface it composes the way to listen")
    func theShellPassesItOn() throws {
        let path = "App/AppShell.swift"
        let found = try lines(of: path).filter { $0.contains("onListen: onListen") }.count

        #expect(
            found == 4,
            """
            \(path) passes onListen to \(found) surface(s), and four were expected — the two \
            phone stacks, the sidebar, and the pane the wide layout draws. A surface left \
            out shows the publication page with no way to start the audio.
            """
        )
    }

    /// The other end of the same wire. `ResumeWiringTests` asserts what `listen()` does with
    /// the chapter; this asserts that the chapter reaches it at all.
    @Test("A chosen chapter reaches the player from the app's own seam")
    func theChosenChapterIsHandedOn() throws {
        let path = "App/StoryArcApp.swift"
        let code = try lines(of: path)

        #expect(
            code.contains { $0.contains("listen(to: publication, at: url, startingAt: part)") },
            """
            \(path) no longer hands the chosen chapter to listen(to:at:startingAt:). Dropping \
            the argument compiles, because the parameter has a default — and every chapter a \
            listener chooses then starts the book where it was left instead.
            """
        )
    }
}
