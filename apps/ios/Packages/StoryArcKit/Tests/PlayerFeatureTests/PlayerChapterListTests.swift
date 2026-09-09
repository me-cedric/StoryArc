import Foundation
import Testing

@testable import PlayerFeature

/// What the player's chapter list states about each chapter.
///
/// `audio-playback`, "Chapters": every chapter carries a mark — finished, in progress, or none
/// at all — the chapter in progress "states how much of itself is left", and "a screen reader
/// hears the chapter, its duration, its mark and the remaining time as one control". The spec
/// asks that of "every surface that lists chapters", and until 2026-09-08 this list marked only
/// the chapter being played and stated no remainder at all.
///
/// **What this is not.** It reads Swift source, because ``ChapterListView`` is a `View` and
/// `swift test` runs on the host with no simulator to compose it in — the reason
/// ``PlayerDockFocusTests`` gives at length. It proves the rule is called and the declarations
/// are attached; it never proves what VoiceOver speaks. Task 15.6 owes a photograph of the list
/// at both text sizes and this does not stand in for it.
///
/// **A grep is a wiring guard and never a proof of behaviour.** So every decision this list
/// makes is a value somewhere else: the three marks, the glyph each is drawn as and the
/// remainder gate are asserted in `ChapterProgressTests`, where they need no view at all. What
/// is left here is whether this file asks for them.
///
/// **Proved able to fail**, per AGENTS.md §5, one mutation per test: replacing `mark.glyph`
/// with a hard-coded `circle`, silencing the mark in progress, reading the remainder at `0`
/// rather than at `centre.place.offset`, moving the row's value back inside the button's label,
/// letting the printed length speak, dropping the `typeSize.isAccessibilitySize` branch, and
/// deleting the German translation of `player.chapter.inProgress`. Each failed its own test by
/// name, and each was reverted.
@Suite("The player's chapter list")
struct PlayerChapterListTests {

    /// The sheet's source, found from this file rather than from the working directory.
    ///
    /// `#filePath` and not a walk up from the process's directory: this repository nests agent
    /// worktrees at `.claude/worktrees/<name>/`, so a walk that climbs looking for a package
    /// root climbs out of the checkout under test.
    private static let sheetsPath: String = {
        var directory = URL(fileURLWithPath: #filePath)
        // …/Tests/PlayerFeatureTests/this file → the package root
        for _ in 0..<3 { directory.deleteLastPathComponent() }
        return directory.appendingPathComponent("Sources/PlayerFeature/PlayerSheets.swift").path
    }()

    /// The sheet's code, comment lines removed.
    ///
    /// The file's own header names the marks and the remainder deliberately, because recording
    /// why they are there is worth more than their presence alone. A search over the raw text
    /// would pass on the paragraph explaining the rule it guards.
    ///
    /// Missing is a failure rather than a skip, and it names the path it looked at: a guard that
    /// cannot find what it guards passes for ever after a rename.
    private func sheetCode() throws -> String {
        let path = Self.sheetsPath
        let text = try #require(
            try? String(contentsOfFile: path, encoding: .utf8),
            "\(path) could not be read — has PlayerSheets.swift moved?"
        )
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The same code with every space and newline dropped.
    ///
    /// For the assertions about *where* a declaration sits: a modifier chain reads the same
    /// whatever it is wrapped at, so a guard on the order of two modifiers must not also be a
    /// guard on the indentation between them.
    private func squeezedCode() throws -> String {
        try sheetCode().filter { !$0.isWhitespace }
    }

    @Test("A finished chapter, the one in progress and one not yet reached each carry their own mark")
    func theThreeMarksAreDrawn() throws {
        let code = try sheetCode()

        #expect(
            code.contains("ChapterProgress.mark("),
            "The list no longer asks ChapterProgress which mark a chapter carries, so it can disagree with the page."
        )
        #expect(
            code.contains("isFinished: centre.hasReachedTheEnd"),
            "A book played to its end no longer marks its chapters finished."
        )
        #expect(
            code.contains("Image(systemName: mark.glyph)"),
            "The row draws a glyph of its own choosing rather than the mark's, so it can draw one no rule chose."
        )
        for word in ["player.chapter.finished", "player.chapter.inProgress"] {
            #expect(
                code.contains("Text(\"\(word)\", bundle: .module)"),
                "The \(word) mark is a silent glyph, so a screen reader hears nothing about it."
            )
        }
    }

    @Test("The chapter in progress states how much of itself is left, from where the audio is now")
    func theRemainderIsDrawn() throws {
        let code = try squeezedCode()

        #expect(
            code.contains("ChapterProgress.remainder(ofChapterLasting:part.duration,mark:mark,at:centre.place.offset)"),
            "The row no longer states what is left of the chapter in progress, from the place the source reports."
        )
        #expect(
            try sheetCode().contains("Text(\"player.chapter.remaining \\(PlaybackClock.time(seconds))\""),
            "The remainder is no longer drawn on the row."
        )
    }

    /// One element, and every fact stated once.
    ///
    /// **The value and the traits belong to the button, not to its label.** Measured on
    /// 2026-09-09: inside the label neither reached the element a screen reader stops on, so a
    /// row read out as "Chapter 3, 8 minutes 32 seconds left, 12:34, button" and stated no mark
    /// at all. The speed sheet and the sleep sheet in the same file put theirs on the button.
    ///
    /// The printed length is silent for the other half of that measurement: it joined the
    /// combined label, so the row stated its length twice and once as a clock face.
    @Test("A row is one element, its length is the button's value, and the printed length is silent")
    func theRowIsOneElement() throws {
        let code = try sheetCode()
        let squeezed = try squeezedCode()

        #expect(
            code.contains(".accessibilityElement(children: .combine)"),
            "A chapter row is no longer one element, so a screen reader reads its glyph apart from its title."
        )
        #expect(
            squeezed.contains(
                ".buttonStyle(.plain).accessibilityValue(Text(part.duration.map(PlaybackClock.spokenTime)??\"\"))"
                    + ".accessibilityAddTraits("
            ),
            "The row's value and traits are not on the button, so neither reaches the element a reader stops on."
        )
        #expect(
            squeezed.contains(".monospacedDigit().accessibilityHidden(true)"),
            "The printed length speaks again, so the row states its length twice and once as a clock face."
        )
        #expect(
            code.contains("Text(\"player.chapter.remaining \\(PlaybackClock.spokenTime(seconds))\""),
            "The remainder is no longer labelled in words, so a screen reader reads it as a clock face."
        )
        // The glyph carries the mark as a word on all three marks — `ChapterMark.glyph`'s
        // partner in `mark(_:)`. A trait saying the same thing makes the row state its mark
        // twice, measured on 2026-09-09: "in progress", then "selected".
        //
        // The chapter row's own trait line, not the file's: the speed sheet and the sleep
        // sheet below it are lists of *choices*, where selected is the only mark there is.
        #expect(
            squeezed.contains(".accessibilityAddTraits(.isButton)"),
            "The chapter row adds a trait beyond the button, so it states its mark twice."
        )
    }

    /// Four items on one row do not fit at the accessibility sizes.
    ///
    /// The project photographed this failure on 2026-09-05 for a row of *two*: a settings value
    /// read `Not an-swering` across three lines of a column a few characters wide, and
    /// `SourceDetail.swift` stacks at `isAccessibilitySize` because of it. This row carries a
    /// mark, a title, a remainder and a length.
    ///
    /// **This asserts the branch, and a photograph asserts the fit** — the division
    /// `SourceDetailSizeTests` draws for the same guard. A host has no window, so what a row
    /// does with the width it is given is not a thing this process can see.
    @Test("The row stacks rather than sharing one line at the accessibility sizes")
    func theRowStacksWhenTheTextIsLargest() throws {
        let code = try sheetCode()

        #expect(
            code.contains("typeSize.isAccessibilitySize"),
            "The row does not ask the text size, so four items share one line at every size."
        )
        #expect(
            code.contains("@Environment(\\.dynamicTypeSize)"),
            "The sheet cannot ask the text size: it does not read it from the environment."
        )
    }

    @Test("Every word this list adds is translated everywhere the app ships")
    func theWordsAreTranslated() throws {
        let catalogue = URL(fileURLWithPath: Self.sheetsPath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let data = try #require(
            try? Data(contentsOf: catalogue),
            "the player's string catalogue is not readable at \(catalogue.path)"
        )
        let parsed = try #require(
            try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            "the player's string catalogue is not JSON"
        )
        let strings = try #require(parsed["strings"] as? [String: Any])

        let keys = ["player.chapter.finished", "player.chapter.inProgress", "player.chapter.remaining %@"]
        for key in keys {
            let record = try #require(
                strings[key] as? [String: Any],
                "the catalogue answers nothing for \(key)"
            )
            let languages = record["localizations"] as? [String: Any] ?? [:]
            for language in ["de", "en", "es", "fr"] {
                #expect(languages[language] != nil, "\(key) has no \(language)")
            }
        }
    }
}
