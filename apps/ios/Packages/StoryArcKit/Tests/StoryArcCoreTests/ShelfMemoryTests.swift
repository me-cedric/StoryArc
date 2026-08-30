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

    @Test("A fit chosen for one series is not the fit every other series opens at")
    func fitIsPerSeries() {
        // The defect this replaced: one key for the whole library, so fit-to-width
        // chosen for a manga changed how every comic in the library opened.
        let memory = ShelfMemory()
            .remembering(ShelfSettings().settingFit(.width), for: .fixedLayout, shelf: "Blame!")
        #expect(memory.theme(for: .fixedLayout, shelf: "Blame!").fit == .width)
        #expect(memory.theme(for: .fixedLayout, shelf: "Bone").fit == .screen)
    }

    @Test("A series never opened takes the fit from the scope's default")
    func fitFallsThroughToTheDefault() {
        let memory = ShelfMemory()
            .settingDefault(ShelfSettings().settingFit(.height), for: .fixedLayout)
            .remembering(ShelfSettings().settingFit(.width), for: .fixedLayout, shelf: "Blame!")
        #expect(memory.theme(for: .fixedLayout, shelf: "Bone").fit == .height)
        // And the default does not sweep a shelf that has already said otherwise.
        #expect(memory.theme(for: .fixedLayout, shelf: "Blame!").fit == .width)
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

    @Test("A reset forgets the defaults and keeps every choice made while reading")
    func resetClearsOnlyDefaults() {
        // `settings-and-about` requires the reset to say that reading progress is not
        // affected. A per-series theme is not progress, but it is equally not a setting —
        // it is a decision made while reading — so it survives too.
        let memory = ShelfMemory()
            .remembering(ShelfSettings(theme: ReadingTheme(preset: .calm)), for: .reflowable, shelf: "Bone")
            .settingDefault(ShelfSettings(theme: ReadingTheme(preset: .focus)), for: .reflowable)
            .clearingDefaults()

        #expect(memory.theme(for: .reflowable, shelf: "Bone").theme.preset == .calm)
        // Back to the built-in default rather than to Focus.
        #expect(memory.theme(for: .reflowable, shelf: "unopened").theme.preset == .paper)
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

    @Test("Reflowable text refuses the two modes that need a picture of a page")
    func reflowableRefusesRasteredModes() {
        let choices = TransitionChoices(
            chosen: .pageCurl, axis: .vertical, reduceMotion: false,
            canCurl: true, isReflowable: true
        )
        // Listed with the reason, not dropped — the spec's "a mode is unavailable for
        // the content" scenario.
        #expect(choices.offered.contains(.pageCurl))
        #expect(choices.unavailable[.pageCurl] == .reflowableText)
        // Fast fade is *not* refused. It needs one raster, a still of the page that is
        // leaving, and the reader takes that before the navigator moves. Curl needs the
        // incoming page as a second texture before it is on screen, which is task 4.3b.
        #expect(choices.isAvailable(.fastFade))
        // Slide is Readium paginated and Scroll is its own preference, so both run.
        #expect(choices.isAvailable(.slide))
        #expect(choices.isAvailable(.verticalScroll))
        #expect(choices.effective == .slide)
        // And the choice survives, so a comic still curls.
        #expect(choices.chosen == .pageCurl)
    }

    @Test("Reduced motion substitutes the fade, which reflowable text can now run")
    func substitutionRespectsTheContent() {
        // Reduce Motion turns Slide into Fast fade, and reflowable text runs Fast fade —
        // so the substitution stands rather than falling back to Slide. A cross-fade is
        // not motion, which is why it is the substitute in the first place.
        let choices = TransitionChoices(
            chosen: .slide, axis: .vertical, reduceMotion: true,
            canCurl: true, isReflowable: true
        )
        #expect(choices.effective == .fastFade)
        // A comic reaches the same answer by the same route.
        let comic = TransitionChoices(
            chosen: .slide, axis: .horizontal, reduceMotion: true, canCurl: true
        )
        #expect(comic.effective == .fastFade)
    }

    @Test("The content check still runs last, so a substitution cannot outvote it")
    func contentCheckRunsLast() {
        // The ordering this protects: Curl honours Reduce Motion by becoming Fast fade,
        // and reflowable text accepts that. But a mode needing two rasters must never
        // survive as `effective` over content that cannot supply them, whichever
        // substitution produced it.
        let choices = TransitionChoices(
            chosen: .pageCurl, axis: .vertical, reduceMotion: false,
            canCurl: true, isReflowable: true
        )
        #expect(choices.effective == .slide)
        #expect(choices.effective.needsTwoRasters == false)
    }

    @Test("Reflowable text offers one scroll row, because prose scrolls the way it reads")
    func reflowableHasNoScrollAxis() {
        let choices = TransitionChoices(
            chosen: .slide, axis: .vertical, reduceMotion: false,
            canCurl: true, isReflowable: true
        )
        #expect(choices.offered.filter(\.isScroll) == [.verticalScroll])
    }

    @Test("Reduce Motion wins over the content reason, because it is the one a reader can undo")
    func reduceMotionWinsOverContent() {
        let choices = TransitionChoices(
            chosen: .pageCurl, axis: .vertical, reduceMotion: true,
            canCurl: true, isReflowable: true
        )
        #expect(choices.unavailable[.pageCurl] == .reduceMotion)
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
        // Nothing chosen means the publication's own metadata still decides.
        #expect(settings.readingDirection == nil)
    }

    // MARK: - Reading direction

    @Test("A direction the reader chose is remembered for that series and no other")
    func directionTravelsWithTheShelf() throws {
        // `comic-reader`: an override "is remembered for the series". Metadata is wrong
        // about this often enough that the reader's answer has to outlive the session.
        let settings = ShelfSettings().settingReadingDirection(.rightToLeft)
        let memory = ShelfMemory().remembering(settings, for: .fixedLayout, shelf: "Blame!")
        let encoded = try JSONEncoder().encode(memory)
        let decoded = try JSONDecoder().decode(ShelfMemory.self, from: encoded)
        #expect(decoded.theme(for: .fixedLayout, shelf: "Blame!").readingDirection == .rightToLeft)
        // A series nobody turned around says nothing, which leaves its own metadata in
        // charge rather than this one's answer.
        #expect(decoded.theme(for: .fixedLayout, shelf: "Bone").readingDirection == nil)
    }

    @Test("Turning a publication around changes nothing else about how it is read")
    func directionLeavesTheModeAlone() {
        let settings = ShelfSettings(transition: .verticalScroll, scrollAxis: .vertical)
            .settingReadingDirection(.rightToLeft)
        #expect(settings.readingDirection == .rightToLeft)
        #expect(settings.transition == .verticalScroll)
        #expect(settings.scrollAxis == .vertical)
    }

    @Test("A page and the position holding it agree one way and mirror the other")
    func positionsMirror() {
        #expect(ReadingDirection.leftToRight.position(0, of: 12) == 0)
        #expect(ReadingDirection.leftToRight.position(11, of: 12) == 11)
        // The first page of a manga is at the far end of the run the pager lays out.
        #expect(ReadingDirection.rightToLeft.position(0, of: 12) == 11)
        #expect(ReadingDirection.rightToLeft.position(11, of: 12) == 0)
    }

    @Test("Turning a publication around keeps the reader on the page they were reading")
    func flippingKeepsThePage() {
        // What `comic-reader`'s "applies immediately without losing the current page"
        // rests on: the run reverses, so the page is read back out of the position it
        // held and then asked for again the new way round.
        let count = 12
        let position = ReadingDirection.leftToRight.position(4, of: count)
        let page = ReadingDirection.leftToRight.position(position, of: count)
        #expect(page == 4)
        #expect(ReadingDirection.rightToLeft.position(page, of: count) == 7)
        // And the same journey back lands where it started, because reversing a run is
        // its own inverse — which is why one function answers both questions.
        #expect(ReadingDirection.leftToRight.position(
            ReadingDirection.rightToLeft.position(7, of: count), of: count
        ) == 4)
    }
}
