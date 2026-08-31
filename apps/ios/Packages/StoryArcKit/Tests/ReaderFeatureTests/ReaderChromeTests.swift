import Foundation
import Testing

/// That revealed chrome is two controls, on both readers, and that neither of them is a
/// fact about the page.
///
/// `comic-reader`, *Revealing controls*:
///
/// > **THEN** exactly two controls fade in over the page — one that closes the publication
/// > and one that opens the reader's menu — and the page does not reflow
/// > **AND** no title, page number, percentage or slider is drawn over the page
///
/// **Why a count and not a list of forbidden controls.** The requirement itself explains
/// it: the previous text named a top bar, a bottom bar and a page slider, and each of the
/// eleven controls between them was added on its own justification. Any wording other than
/// a count invites a twelfth. So this suite counts.
///
/// **Why it reads the source text, which is the second-best test.** The honest test taps
/// the centre of a booted simulator and counts what is hittable, and this repository has
/// one — `apps/ios/UITests` — that no gate runs. `pnpm test:ios` runs `swift test` on the
/// host, where there is no screen to hit. `ReaderRoutingWiringTests` and Android's
/// `ReaderChromeWiringTest` are the same choice made for the same reason, and both carry
/// the same warning: this is a tripwire, not a proof. It says the chrome declares two
/// buttons; it never says two buttons appeared.
///
/// Delete it the day a run of `StoryArcUITests` is a gate — that run reveals the chrome in
/// both readers and would fail on a third control by itself.
@Suite("Revealed chrome is two controls")
struct ReaderChromeTests {

    /// The package directory, from this test's own compiled path.
    ///
    /// `#filePath` and not a walk up from the working directory: this repository nests agent
    /// worktrees at `.claude/worktrees/<name>/`, and a walk that climbs looking for a marker
    /// leaves the checkout under test and guards the parent's copy — which is how the Android
    /// counterpart of this idea came to pass against a file that was never built.
    private static let package: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The comic reader's chrome.
    private static var comicChrome: URL {
        package.appending(path: "Sources/ReaderFeature/ReaderChrome.swift")
    }

    /// The comic reader's view, which owns whether its chrome is drawn.
    private static var comicReaderView: URL {
        package.appending(path: "Sources/ReaderFeature/ReaderView.swift")
    }

    /// The reflowable reader's view, for the same reason.
    private static var reflowableReaderView: URL {
        package
            .deletingLastPathComponent()
            .appending(path: "StoryArcEpub/Sources/EpubReaderFeature/EpubReaderView.swift")
    }

    /// The reflowable reader's chrome.
    ///
    /// `StoryArcEpub` is reached as `../StoryArcEpub`, which is where `Package.swift`
    /// declares it as a path dependency, and is the same crossing
    /// `SolidArchiveHasNoNoticeTests` makes for the same reason: this suite runs on the host
    /// and that package's own tests need a simulator, so no gate reaches them.
    private static var reflowableChrome: URL {
        package
            .deletingLastPathComponent()
            .appending(path: "StoryArcEpub/Sources/EpubReaderFeature/EpubReaderChrome.swift")
    }

    /// A chrome file's code, with its prose removed.
    ///
    /// Comments are stripped before anything is counted, because this codebase explains
    /// itself at length and every one of the words below appears in a comment somewhere. A
    /// guard that counted the word "Button" in a paragraph about buttons would be measuring
    /// the documentation.
    ///
    /// Missing is a failure and it names the path it looked at. A guard that cannot find
    /// what it guards has to say so, or it passes for ever after a rename.
    private func code(of url: URL) throws -> String {
        let text = try #require(
            try? String(contentsOf: url, encoding: .utf8),
            "\(url.path) could not be read — has the reader's chrome moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// How many times `word` appears in `code` as a whole word.
    ///
    /// Whole-word, so `buttonStyle` is not a `Button` and `ChromeButtonStyle` is not one
    /// either. Hand-rolled rather than a `Regex`, because building one throws and a guard
    /// should not be able to fail for a reason that has nothing to do with what it guards.
    private func occurrences(of word: String, in code: String) -> Int {
        func isWord(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_"
        }
        var count = 0
        var from = code.startIndex
        while let found = code.range(of: word, range: from..<code.endIndex) {
            let leftIsWord = found.lowerBound > code.startIndex
                && isWord(code[code.index(before: found.lowerBound)])
            let rightIsWord = found.upperBound < code.endIndex && isWord(code[found.upperBound])
            if !leftIsWord && !rightIsWord { count += 1 }
            from = found.upperBound
        }
        return count
    }

    /// What may not be drawn over the page, and the word that would put it there.
    ///
    /// A slider and a picker are controls, so the count would already catch a `Picker` — but
    /// not a `Slider`, which is not a `Button`. The text facts are not controls at all and no
    /// count reaches them, which is why the requirement names them separately: they are the
    /// furniture that made the chrome a fifth of a screen.
    private static let forbidden: [(what: String, spelling: String)] = [
        ("a page slider", "Slider"),
        ("a picker", "Picker"),
        ("the page count", "pageCountLabel"),
        ("the page-slider row", "pageSliderRow"),
        ("the chapter row", "chapterRow"),
        ("the thumbnail strip", "ThumbnailStrip"),
        ("the layout controls", "ReaderLayoutControls"),
        ("a percentage", "progression"),
        ("the chapter title", "chapterTitle"),
    ]

    /// The two assertions, run against one reader's chrome.
    private func expectTwoControls(in url: URL, reader: String) throws {
        let code = try code(of: url)
        let buttons = occurrences(of: "Button", in: code)

        #expect(
            buttons == 2,
            """
            \(reader)'s chrome declares \(buttons) buttons, not two. `comic-reader` \
            requires exactly two controls over the page: one that closes the publication \
            and one that opens the menu. A third belongs behind the menu, labelled in \
            words — that is the whole point of the count.
            """
        )

        for banned in Self.forbidden {
            #expect(
                occurrences(of: banned.spelling, in: code) == 0,
                """
                \(reader)'s chrome draws \(banned.what) — `\(banned.spelling)` appears in \
                it. `comic-reader` forbids a title, a page number, a percentage or a \
                slider over the page, because each of those is a fact the menu states \
                better and none of them is an action. Move it onto a menu row.
                """
            )
        }
    }

    /// The two controls are shown on arrival and take themselves away.
    ///
    /// Pinned because a screenshot pair caught the opposite of what the requirement said.
    /// *Entering the reader* read "chrome is hidden", and **no reader had ever done that** —
    /// all four start it visible and withdraw it after a timeout, and no source-level test
    /// looked at the arrival frame, so the divergence outlived every gate the requirement
    /// has had. The delta now describes what happens and says why it is the better half:
    /// a reader who has just opened a book has not yet learned that a centre tap brings the
    /// way out back, and showing it once is the only place that can be taught.
    ///
    /// So this asserts the **decision**, not the accident. If either reader is ever changed
    /// to start hidden, this fails and whoever did it has to change the requirement too,
    /// rather than the two drifting apart again in silence.
    @Test(
        "Both readers show the two controls on arrival, and both take them away by themselves",
        arguments: [
            (Self.comicReaderView, "wantsChrome", "The comic reader"),
            (Self.reflowableReaderView, "isChromeVisible", "The reflowable reader"),
        ]
    )
    func chromeArrivesThenWithdraws(view: URL, state: String, reader: String) throws {
        let source = try code(of: view)

        #expect(
            source.contains("\(state) = true"),
            """
            \(reader) no longer shows its controls on arrival.
            That is a requirement change and not a tidy-up — see quiet-reader's comic-reader delta.
            """
        )
        // And it still takes them away without being asked. A reader that showed them on
        // arrival and kept them would satisfy the line above and none of the intent.
        #expect(
            source.contains("\(state) = false"),
            "\(reader) never withdraws its controls, so the page is never alone."
        )
    }

    @Test("The comic reader reveals a way out and a way in, and nothing else")
    func comicReader() throws {
        try expectTwoControls(in: Self.comicChrome, reader: "The comic reader")
    }

    @Test("The reflowable reader reveals a way out and a way in, and nothing else")
    func reflowableReader() throws {
        try expectTwoControls(in: Self.reflowableChrome, reader: "The reflowable reader")
    }
}
