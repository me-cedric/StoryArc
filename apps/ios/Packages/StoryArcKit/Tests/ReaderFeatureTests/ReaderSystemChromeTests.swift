import Foundation
import Testing

/// What the reader takes from the device while it is open, and gives back on the way out.
///
/// `comic-reader`, *Screen stays awake*:
///
/// > **THEN** the screen does not auto-lock while a page is visible, and normal locking
/// > resumes on leaving
///
/// `comic-reader`, *Orientation lock*:
///
/// > **THEN** it stays locked for the reader only, and the rest of the app follows the device
///
/// **Both scenarios are one rule and the same failure.** Each takes a device-wide setting for
/// the length of a reading session, and each is wrong in the same way if it is not handed
/// back: a reader who leaves the publication and finds their phone will not sleep, or will
/// not rotate, has been left worse off by a reader they closed. Neither half can be seen in a
/// screenshot, and neither is something a reader reports as a reader bug.
///
/// **Why it reads the source text, which is the second-best test.** `isIdleTimerDisabled` is
/// a property of the running application and the orientation mask is answered to the
/// application delegate; both need a booted simulator, and no gate in this repository runs
/// one. `ReaderChromeTests` and `TapZoneWiringTests` are the same choice made for the same
/// reason and carry the same warning: this is a tripwire, not a proof. It says the modifier
/// writes the value back on the way out; it never says the device slept.
@Suite("The reader gives the device back on the way out")
struct ReaderSystemChromeTests {

    /// The package directory, from this test's own compiled path. See `ReaderChromeTests`
    /// for why this is `#filePath` and not a walk up from the working directory.
    private static let package: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static var modifier: URL {
        package.appending(path: "Sources/ReaderFeature/ReaderSystemChrome.swift")
    }

    /// The modifier's code, with its prose removed.
    ///
    /// Comments are stripped first: this file explains both rules in its own words, and a
    /// guard that found `isIdleTimerDisabled` in a paragraph about the idle timer would be
    /// measuring the documentation.
    private func code() throws -> String {
        let text = try #require(
            try? String(contentsOf: Self.modifier, encoding: .utf8),
            "\(Self.modifier.path) could not be read — has the reader's system chrome moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let comment = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<comment.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// Only what the reader does as it leaves.
    ///
    /// A claim about giving something back has to be measured where it is given back.
    /// Reading the whole file would pass on a modifier that wrote `false` on the way *in*.
    private func leaving() throws -> String {
        let code = try code()
        let opening = try #require(
            code.range(of: ".onDisappear {"),
            """
            `ReaderSystemChrome` has no `.onDisappear`. Everything it takes from the device \
            is taken for the length of a reading session, and there is nowhere else to give \
            it back.
            """
        )
        let rest = code[opening.upperBound...]
        let closing = try #require(
            rest.range(of: "\n            }"),
            "`.onDisappear` is not closed where this guard expects it."
        )
        return String(rest[..<closing.lowerBound])
    }

    @Test("The screen is held awake on arrival and released on the way out")
    func theIdleTimerIsHandedBack() throws {
        let code = try code()
        let leaving = try leaving()
        #expect(
            code.contains(".onAppear { UIApplication.shared.isIdleTimerDisabled = true }"),
            """
            The reader no longer stops the screen locking. `comic-reader`: "the screen does \
            not auto-lock while a page is visible". A long look at one page is reading, not \
            idling.
            """
        )
        #expect(
            leaving.contains("isIdleTimerDisabled = false"),
            """
            The reader no longer lets the screen lock again on the way out. `comic-reader`: \
            "normal locking resumes on leaving". A phone that stopped sleeping and was never \
            told it may again is the worse half of this scenario, and it outlives the reader \
            that caused it.
            """
        )
    }

    @Test("The home indicator dims with the rest of the chrome")
    func theHomeIndicatorDimsWithTheChrome() throws {
        let code = try code()
        #expect(
            code.contains(
                ".persistentSystemOverlays(isChromeVisible ? .automatic : .hidden)"
            ),
            """
            The reader no longer dims the home indicator with the rest of the chrome. Its \
            own doc comment requires it, and `SystemBars.kt` already does it on Android.
            """
        )
    }

    @Test("The orientation lock is the reader's own, and is given back on the way out")
    func theOrientationIsHandedBack() throws {
        let code = try code()
        let leaving = try leaving()
        #expect(
            code.contains("ReaderOrientation.hold()")
                && code.contains("of: isOrientationLocked"),
            """
            The reader no longer holds the orientation when it is asked to. `comic-reader` \
            requires a locked reader to stay "locked for the reader only".
            """
        )
        #expect(
            leaving.contains("ReaderOrientation.release()"),
            """
            The reader no longer releases the orientation on the way out. `comic-reader`: \
            "the rest of the app follows the device". A mask narrowed to one orientation and \
            never widened again holds the whole app there, and nothing outside the reader \
            offers a way to undo it.
            """
        )
    }
}
