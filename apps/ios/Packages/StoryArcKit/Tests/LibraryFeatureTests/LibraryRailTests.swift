import Foundation
import StoryArcCore
import Testing

@testable import LibraryFeature

/// Which letters the index offers, and the five sorts under which it offers none.
///
/// `library-browsing`'s *An index down the side of a long shelf* and *A sort no letter
/// describes* scenarios are what these cases hold. Android's `LibraryRailTest` answers the
/// same ones.
struct LibraryRailTests {

    private func issue(_ title: String, series: String? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/\(title)"),
            format: .cbz,
            displayTitle: title,
            series: series,
            origin: .embedded
        )
    }

    /// Thirteen publications, which is one more than ``LibrarySections/threshold``.
    private func thirteen(_ titles: [String]) -> [Publication] {
        #expect(titles.count > LibrarySections.threshold)
        return titles.map { issue($0) }
    }

    private let letters = [
        "Ashfall", "Blackwater", "Cinder", "Drift", "Ember", "Fathom", "Glass",
        "Harrow", "Ironwood", "Jubilee", "Kestrel", "Lantern", "Moth",
    ]

    @Test("A title sort offers one entry per letter the shelf files a row under")
    func titleSort() {
        let entries = LibraryRail.of(thirteen(letters), sort: .title, locale: Locale(identifier: "en"))

        #expect(entries.map(\.label) == ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M"])
        #expect(entries[0].publicationID == thirteen(letters)[0].id)
    }

    /// The sort key, not the raw title. `library-browsing` alphabetises a title with its
    /// leading article ignored, so a label read off the raw title would say T in the middle
    /// of the S run and the index would stop describing the shelf.
    @Test("The Sandman files under S")
    func articlesAreIgnored() {
        var titles = letters
        titles[0] = "The Sandman"
        let entries = LibraryRail.of(thirteen(titles), sort: .title, locale: Locale(identifier: "en"))

        #expect(entries.first?.label == "S")
        #expect(!entries.map(\.label).contains("T"))
    }

    @Test("A title no letter claims is offered as #")
    func nonLetter() {
        var titles = letters
        titles[0] = "2000 AD"
        let entries = LibraryRail.of(thirteen(titles), sort: .title, locale: Locale(identifier: "en"))

        #expect(entries.first?.label == "#")
    }

    @Test("Five sorts file nothing under a letter, and offer no index at all")
    func noIndexForContinuousSorts() {
        for sort in [LibrarySort.lastRead, .progress, .year, .dateAdded, .fileSize] {
            #expect(LibraryRail.of(thirteen(letters), sort: sort, locale: Locale(identifier: "en")).isEmpty)
        }
    }

    /// The whole of the hide-rather-than-disable decision: the caller draws nothing, so no
    /// reader meets a control that refuses every touch.
    @Test("A shelf short enough to scan offers no index")
    func shortShelf() {
        let short = Array(letters.prefix(LibrarySections.threshold)).map { issue($0) }

        #expect(short.count == LibrarySections.threshold)
        #expect(LibraryRail.of(short, sort: .title, locale: Locale(identifier: "en")).isEmpty)
    }

    @Test("One letter over the whole shelf is a label rather than an index")
    func oneLetter() {
        let all = (1...13).map { issue("Ashfall #\($0)") }

        #expect(LibraryRail.of(all, sort: .title, locale: Locale(identifier: "en")).isEmpty)
    }

    /// `LibraryIndex.compareBySeries` puts every series-less publication after every series,
    /// in one pile, so the `#` entry is one contiguous run at the end rather than a second
    /// alphabet run through the first.
    @Test("A series sort files a publication naming no series under #")
    func seriesSort() {
        var shelf = (1...10).map { issue("issue \($0)", series: "Lantern") }
        shelf += (1...3).map { issue("loose \($0)") }
        let entries = LibraryRail.of(shelf, sort: .series, locale: Locale(identifier: "en"))

        #expect(entries.map(\.label) == ["L", "#"])
        #expect(entries[1].publicationID == shelf[10].id)
    }

    @Test("A repeated letter is one entry, pointing at the first row under it")
    func distinctInShelfOrder() {
        var shelf = [issue("Ashfall"), issue("Blackwater")]
        shelf += (1...11).map { issue("Ashfall #\($0)") }
        let entries = LibraryRail.of(shelf, sort: .title, locale: Locale(identifier: "en"))

        #expect(entries.map(\.label) == ["A", "B"])
        #expect(entries[0].publicationID == shelf[0].id)
    }

    /// Uppercased for the reader's locale rather than for the machine's, the rule
    /// ``LibrarySections`` already applies to a heading — so a heading and an index entry
    /// cannot disagree about one row.
    @Test("A Turkish shelf files ısı under I")
    func turkishLocale() {
        var shelf = [issue("ısı")]
        shelf += (1...12).map { issue("Zephyr \($0)") }
        let entries = LibraryRail.of(shelf, sort: .title, locale: Locale(identifier: "tr"))

        #expect(entries.map(\.label) == ["I", "Z"])
    }

    /// The index jumps to a row, and headings change what the shelf draws around that row.
    ///
    /// The list layout divides now — ``LibrarySections/divide(_:by:columns:locale:)`` at one
    /// column — so the rows the rail addresses sit inside sections. Two things have to hold
    /// for a letter to land where it says: the sections are contiguous runs of the same
    /// arranged shelf, so no row moves, and the first row of the section headed by a letter
    /// is the row the rail points at. A regrouping, or an entry pointing at a row in the
    /// middle of its section, would scroll the reader somewhere they did not ask for.
    @Test("With the headings drawn, a letter still jumps to the first row filed under it")
    func jumpTargetsSurviveTheHeadings() {
        let shelf = Array("ABCDEFGHIJKLMNOPQRSTUVWXY").enumerated().flatMap { index, letter in
            (1...(index < 22 ? 2 : 1)).map { issue("\(letter)shfall \($0)") }
        }
        let english = Locale(identifier: "en")
        let sections = LibrarySections.divide(shelf, by: .title, columns: 1, locale: english)
        let entries = LibraryRail.of(shelf, sort: .title, locale: english)

        #expect(shelf.count == 47)
        #expect(sections.count == 25, "the list divides this shelf")
        #expect(entries.map(\.label) == sections.map(\.title))
        for (entry, section) in zip(entries, sections) {
            #expect(entry.publicationID == section.publications.first?.id)
        }
        #expect(sections.flatMap(\.publications).map(\.id) == shelf.map(\.id), "a row moved")
    }

    /// **The row a letter names is never behind its own heading.**
    ///
    /// A pinned heading is drawn over the top of the scroll view, so a row anchored there is
    /// covered by it. Measured on Android on 2026-09-11, where the arithmetic is explicit: the
    /// row spanned 1043 to 1259 and the heading 1043 to 1106, so 63 px of a 216 px row was
    /// hidden. ``LibraryRail/anchors(sections:)`` is the answer on this platform, and the two
    /// headings carry the identifiers it names — `SectionedShelf` and `CoverList`.
    @Test("A letter that names a section scrolls to its heading")
    func anchorsNameTheHeading() {
        let ashfall = (1...3).map { issue("Ashfall \($0)") }
        let bellwether = (1...3).map { issue("Bellwether \($0)") }
        let sections = [
            LibrarySection(id: "0.A", title: "A", publications: ashfall),
            LibrarySection(id: "1.B", title: "B", publications: bellwether),
        ]

        let anchors = LibraryRail.anchors(sections: sections)

        #expect(anchors[ashfall[0].id] == "0.A")
        #expect(anchors[bellwether[0].id] == "1.B")
        #expect(anchors[ashfall[1].id] == nil, "a row no heading names is scrolled to itself")
        #expect(LibraryRail.anchors(sections: []).isEmpty, "an undivided shelf names no heading")
    }

    /// `21.1-ios`: 27 entries of 22 pt need about 600 pt, more than a landscape shelf offers.
    /// The collapse is what keeps the rail on screen instead of running off both edges.
    private func alphabet(_ letters: String) -> [RailEntry] {
        letters.map { RailEntry(label: String($0), publicationID: String($0)) }
    }

    @Test("A rail short enough to fit draws every entry")
    func collapsedKeepsEverythingThatFits() {
        let entries = alphabet("ABCDEFGHIJ")

        #expect(LibraryRail.collapsed(entries, toFit: 400, entryHeight: 22) == entries)
    }

    @Test("A rail too tall for its space collapses to an evenly spaced subset")
    func collapsedThinsAnOverflowingRail() {
        let entries = alphabet("ABCDEFGHIJKLMNOPQRSTUVWXYZ#") // 27, the field case

        let shown = LibraryRail.collapsed(entries, toFit: 300, entryHeight: 22)

        #expect(shown.count <= 13, "300 / 22 fits at most 13 rows")
        #expect(shown.first == entries.first, "the start of the alphabet is kept")
        #expect(shown.last == entries.last, "the end of the alphabet is kept")
        #expect(Set(shown.map(\.id)).count == shown.count, "no letter is offered twice")
    }

    @Test("A space too short for even one row still offers the first letter")
    func collapsedNeverOffersNothing() {
        let entries = alphabet("ABCDEFGHIJKLMNOPQRSTUVWXYZ#")

        #expect(LibraryRail.collapsed(entries, toFit: 10, entryHeight: 22) == [entries[0]])
    }

    @Test("A non-positive height or entry size changes nothing, rather than dividing by it")
    func collapsedRefusesToDivideByNothing() {
        let entries = alphabet("ABC")

        #expect(LibraryRail.collapsed(entries, toFit: 0, entryHeight: 22) == entries)
        #expect(LibraryRail.collapsed(entries, toFit: 100, entryHeight: 0) == entries)
    }

    // MARK: One scrubber

    /// `close-the-audited-gaps` 24.6: the rail is one control, and a finger dragged down it
    /// chooses the letters in order, each once.
    private var rail: [RailEntry] { alphabet("ABCDEFGHIJKLMNOPQRSTUVWXYZ#") }
    private var railHeight: CGFloat { 27 * 22 + 2 * LibraryRail.inset }

    @Test("A finger dragged down the whole rail chooses every letter, in order, once each")
    func aDragChoosesLettersInOrder() {
        var scrub = RailScrub()
        var chosen: [Int] = []
        var y: CGFloat = 0
        while y <= railHeight {
            if let index = scrub.move(to: y, height: railHeight, inset: LibraryRail.inset, count: rail.count) {
                chosen.append(index)
            }
            y += 1
        }

        #expect(chosen == Array(0..<rail.count))
    }

    @Test("A finger dragged back up chooses the letters in reverse")
    func aDragUpChoosesLettersInReverse() {
        var scrub = RailScrub()
        var chosen: [Int] = []
        var y = railHeight
        while y >= 0 {
            if let index = scrub.move(to: y, height: railHeight, inset: LibraryRail.inset, count: rail.count) {
                chosen.append(index)
            }
            y -= 1
        }

        #expect(chosen == Array((0..<rail.count).reversed()))
    }

    @Test("A letter is chosen once while the finger stays on it, and again after the finger lifts")
    func aLetterIsChosenOnArrival() {
        var scrub = RailScrub()
        let middle = LibraryRail.inset + 22 * 3 + 5

        #expect(scrub.move(to: middle, height: railHeight, inset: LibraryRail.inset, count: rail.count) == 3)
        #expect(scrub.move(to: middle + 4, height: railHeight, inset: LibraryRail.inset, count: rail.count) == nil)
        scrub.end()
        #expect(scrub.current == nil)
        #expect(scrub.move(to: middle, height: railHeight, inset: LibraryRail.inset, count: rail.count) == 3)
    }

    @Test("A tap on a letter chooses that letter")
    func aTapChoosesTheLetterUnderIt() {
        for target in [0, 9, 26] {
            // Both edges of the letter's own 22 points, so a rail that drifts off its letters fails.
            let top = LibraryRail.inset + 22 * CGFloat(target) + 0.5
            let bottom = LibraryRail.inset + 22 * CGFloat(target + 1) - 0.5

            for y in [top, bottom] {
                #expect(
                    RailScrub.index(at: y, height: railHeight, inset: LibraryRail.inset, count: rail.count) == target
                )
            }
        }
    }

    @Test("The padding above and below the letters counts as the first and the last")
    func theEdgesAreTheEnds() {
        #expect(RailScrub.index(at: -30, height: railHeight, inset: LibraryRail.inset, count: 27) == 0)
        #expect(RailScrub.index(at: railHeight + 30, height: railHeight, inset: LibraryRail.inset, count: 27) == 26)
    }

    @Test("A rail that draws fewer letters than it holds still reaches every one of them")
    func aThinnedRailStillReachesEveryLetter() {
        let drawn = LibraryRail.collapsed(rail, toFit: 150, entryHeight: 22)
        let height = CGFloat(drawn.count) * 22 + 2 * LibraryRail.inset
        var scrub = RailScrub()
        var chosen: [Int] = []
        var y: CGFloat = 0
        while y <= height {
            if let index = scrub.move(to: y, height: height, inset: LibraryRail.inset, count: rail.count) {
                chosen.append(index)
            }
            y += 0.5
        }

        #expect(drawn.count < rail.count)
        #expect(chosen == Array(0..<rail.count))
    }

    @Test("Nothing to choose answers nothing")
    func anEmptyRailChoosesNothing() {
        var scrub = RailScrub()

        #expect(scrub.move(to: 10, height: 100, inset: 8, count: 0) == nil)
        #expect(RailScrub.step(from: nil, by: 1, count: 0) == nil)
    }

    @Test("VoiceOver steps to the next and the previous letter, and stops at the ends")
    func adjustableStepsStopAtTheEnds() {
        #expect(RailScrub.step(from: nil, by: 1, count: 27) == 0)
        #expect(RailScrub.step(from: nil, by: -1, count: 27) == 26)
        #expect(RailScrub.step(from: 4, by: 1, count: 27) == 5)
        #expect(RailScrub.step(from: 4, by: -1, count: 27) == 3)
        #expect(RailScrub.step(from: 26, by: 1, count: 27) == 26)
        #expect(RailScrub.step(from: 0, by: -1, count: 27) == 0)
    }

    /// The parts of the rail a unit test cannot drive: the gesture, the haptic and the
    /// accessibility. Read as text, the way `LibraryGroupingWiringTests` reads the shelf.
    @Test("The rail is one gesture with a tick, an adjustable value and named jump actions")
    func theRailIsWiredAsOneControl() {
        let code = LibraryFeatureSource.code(of: "Sources/LibraryFeature/IndexRail.swift")

        #expect(code.contains("DragGesture(minimumDistance: 0)"), "a tap and a drag are one gesture")
        #expect(code.contains(".storyArcFeedback(.selection, trigger: scrub.current"), "a tick on each new letter")
        #expect(code.contains(".accessibilityAdjustableAction"), "VoiceOver steps letter by letter")
        #expect(code.contains(".accessibilityActions"), "each letter stays a named jump")
    }
}
