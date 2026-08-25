import Foundation
import Testing

@testable import StoryArcCore

/// What a shelf is read with, and which transitions it may be read with.
///
/// `reading-themes` scopes a theme to the series with a global default per scope, and
/// `comic-reader` repeats that rule word for word for the reading mode — so the two
/// share one store, and these are its tests. Android's twin asserts the same table.
@Suite("Shelf memory")
struct ShelfMemoryTests {

    // MARK: - Remembering

    @Test("A theme set on one book in a series is what the next book in it opens with")
    func perSeriesMemory() {
        let chosen = ShelfSettings(theme: ReadingTheme(preset: .calm))
        let memory = ShelfMemory()
            .remembering(chosen, for: .reflowable, shelf: "Bone")
        #expect(memory.theme(for: .reflowable, shelf: "Bone").theme.preset == .calm)
        // A shelf never opened falls through to the default, not to the last book read.
        #expect(memory.theme(for: .reflowable, shelf: "Blame!").theme.preset == .paper)
    }

    @Test("Reflowable and fixed-layout keep separate defaults for the same shelf name")
    func scopesDoNotCollide() {
        // A series called "Bone" can hold both a comic and an ebook, and a line height
        // means nothing to a page of artwork.
        let memory = ShelfMemory()
            .remembering(ShelfSettings(theme: ReadingTheme(preset: .calm)), for: .reflowable, shelf: "Bone")
            .remembering(ShelfSettings(theme: ReadingTheme(preset: .quiet)), for: .fixedLayout, shelf: "Bone")
        #expect(memory.theme(for: .reflowable, shelf: "Bone").theme.preset == .calm)
        #expect(memory.theme(for: .fixedLayout, shelf: "Bone").theme.preset == .quiet)
    }

    @Test("Changing the global default leaves a choice already made alone")
    func defaultDoesNotOverwriteAShelf() {
        let memory = ShelfMemory()
            .remembering(ShelfSettings(theme: ReadingTheme(preset: .calm)), for: .reflowable, shelf: "Bone")
            .settingDefault(ShelfSettings(theme: ReadingTheme(preset: .focus)), for: .reflowable)
        #expect(memory.theme(for: .reflowable, shelf: "Bone").theme.preset == .calm)
        #expect(memory.theme(for: .reflowable, shelf: "unopened").theme.preset == .focus)
        // And it does not leak across scopes.
        #expect(memory.theme(for: .fixedLayout, shelf: "unopened").theme.preset == .paper)
    }

    @Test("A book with no series is a series of one, not the global default")
    func standaloneBookIsItsOwnShelf() {
        // Otherwise reading one novel in sepia would change every other book.
        #expect(ShelfMemory.shelf(series: "Bone", identity: "abc") == "Bone")
        #expect(ShelfMemory.shelf(series: nil, identity: "abc") == "abc")
        #expect(ShelfMemory.shelf(series: "   ", identity: "abc") == "abc")
    }

    @Test("A deviation survives a round trip, because the values travel with the theme")
    func deviationsSurvive() throws {
        var values = ThemePreset.paper.values
        values.lineHeight = 2.1
        let stored = ShelfSettings(
            theme: ReadingTheme(preset: .paper, deviations: [.lineSpacing]),
            values: values
        )
        let memory = ShelfMemory().remembering(stored, for: .reflowable, shelf: "Bone")
        let encoded = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(ShelfMemory.self, from: encoded)
        let read = decoded.theme(for: .reflowable, shelf: "Bone")
        #expect(read.values.lineHeight == 2.1)
        #expect(read.theme.isModified)
    }

    @Test("A custom palette survives a round trip too")
    func customColoursSurvive() throws {
        let palette = ReaderPalette.derived(name: "Sea", background: "#0B2027")
        let stored = ShelfSettings(theme: ReadingTheme().adopting(palette))
        let memory = ShelfMemory().remembering(stored, for: .reflowable, shelf: "Bone")
        let encoded = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(ShelfMemory.self, from: encoded)
        #expect(decoded.theme(for: .reflowable, shelf: "Bone").theme.custom == palette)
    }

    // MARK: - Transition choices

    @Test("Reduce Motion leaves the animated modes listed and marked, and runs the fade")
    func reduceMotionMarksRatherThanHides() {
        let choices = TransitionChoices(
            chosen: .pageCurl, axis: .vertical, reduceMotion: true, canCurl: true
        )
        // Listed, because "a control that vanishes teaches the user nothing".
        #expect(choices.offered.contains(.pageCurl))
        #expect(choices.unavailable[.pageCurl] == .reduceMotion)
        #expect(choices.unavailable[.slide] == .reduceMotion)
        #expect(choices.isAvailable(.fastFade))
        #expect(choices.effective == .fastFade)
        // And the choice is not rewritten — turning the setting off restores it.
        #expect(choices.chosen == .pageCurl)
    }

    @Test("A device that cannot curl omits the row rather than showing a dead one")
    func absentCurlIsAbsent() {
        let choices = TransitionChoices(
            chosen: .pageCurl, axis: .vertical, reduceMotion: false, canCurl: false
        )
        #expect(!choices.offered.contains(.pageCurl))
        #expect(choices.curlIsAbsent)
        // Slide is the stated fallback, and every other mode stays available.
        #expect(choices.effective == .slide)
        #expect(choices.offered.contains(.slide))
        #expect(choices.offered.contains(.fastFade))
        // The stored preference survives the device that cannot honour it.
        #expect(choices.chosen == .pageCurl)
    }

    @Test("Both scroll rows are offered, the implied axis first — that is the override")
    func bothScrollRowsAreOffered() {
        // `page-transitions` requires the axis to be "separately overridable", and two
        // rows are that override with no second control for the reader to find.
        let vertical = TransitionChoices(
            chosen: .slide, axis: .vertical, reduceMotion: false, canCurl: true
        )
        #expect(
            vertical.offered == [.pageCurl, .slide, .fastFade, .verticalScroll, .horizontalScroll]
        )
        #expect(vertical.impliedAxis == .vertical)

        let horizontal = TransitionChoices(
            chosen: .slide, axis: .horizontal, reduceMotion: false, canCurl: true
        )
        #expect(
            horizontal.offered == [.pageCurl, .slide, .fastFade, .horizontalScroll, .verticalScroll]
        )
    }

    @Test("A tall publication scrolls vertically without being told it is a webtoon")
    func tallPagesImplyVertical() {
        // A webtoon that declares nothing is still one tall strip cut into files.
        #expect(
            ScrollAxis.implied(isReflowable: false, isTall: true, declaresHorizontal: true)
                == .vertical
        )
        #expect(
            ScrollAxis.implied(isReflowable: true, isTall: false, declaresHorizontal: true)
                == .vertical
        )
        #expect(
            ScrollAxis.implied(isReflowable: false, isTall: false, declaresHorizontal: true)
                == .horizontal
        )
        #expect(
            ScrollAxis.implied(isReflowable: false, isTall: false, declaresHorizontal: false)
                == .vertical
        )
    }

    @Test("Reduce Motion does not touch the scroll modes, which are not animations")
    func scrollSurvivesReduceMotion() {
        let choices = TransitionChoices(
            chosen: .verticalScroll, axis: .vertical, reduceMotion: true, canCurl: true
        )
        #expect(choices.effective == .verticalScroll)
        #expect(choices.isAvailable(.verticalScroll))
    }

    @Test("The transition is remembered per shelf, alongside the theme")
    func transitionTravelsWithTheShelf() throws {
        let settings = ShelfSettings(transition: .verticalScroll, scrollAxis: .vertical)
        let memory = ShelfMemory().remembering(settings, for: .fixedLayout, shelf: "Bone")
        let encoded = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(ShelfMemory.self, from: encoded)
        #expect(decoded.theme(for: .fixedLayout, shelf: "Bone").transition == .verticalScroll)
        // And it does not leak into the reflowable scope.
        #expect(decoded.theme(for: .reflowable, shelf: "Bone").transition == .slide)
    }

    @Test("Settings written before the transition existed still decode")
    func oldSettingsDecode() throws {
        // Swift's synthesised decoder fails on a missing key even with a default, so a
        // build that adds a field could otherwise not read what an earlier one wrote.
        let json = Data(#"{"theme":{"preset":"calm","deviations":[]}}"#.utf8)
        let settings = try JSONDecoder().decode(ShelfSettings.self, from: json)
        #expect(settings.theme.preset == .calm)
        #expect(settings.transition == .slide)
        #expect(settings.scrollAxis == nil)
    }
}
