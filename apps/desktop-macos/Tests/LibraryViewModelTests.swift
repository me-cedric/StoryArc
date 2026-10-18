import Foundation
import LibraryFeature
import Persistence
import StoryArcCore
import Testing

@testable import StoryArc

/// The grid and the list of task 2.23a, over StoryArcKit's own library store: empty, ten
/// thousand publications, grouping by series, single selection and modifier-click.
@MainActor
@Suite("Library view model")
struct LibraryViewModelTests {
    private func model() throws -> (LibraryModel, ScratchDefaults) {
        let scratch = try ScratchDefaults(prefix: "mac-library-")
        let folder = URL.temporaryDirectory.appending(path: scratch.name, directoryHint: .isDirectory)
        let model = LibraryModel(
            progress: nil, bookmarks: nil, documents: folder,
            preferences: LibraryPreferences(defaults: scratch.defaults),
            cache: LibraryCache(directory: folder)
        )
        return (model, scratch)
    }

    @Test("An empty library shows nothing and is not narrowed")
    func emptyLibrary() throws {
        let (model, scratch) = try model()
        defer { scratch.remove() }
        #expect(model.visible.isEmpty)
        #expect(!model.query.isNarrowed)
        #expect(LibraryGrid.columns(for: 0).isEmpty)
    }

    @Test("Ten thousand publications arrange under a second and group by series")
    func tenThousand() throws {
        let (model, scratch) = try model()
        defer { scratch.remove() }
        let publications = (0..<10_000).map { TestPublications.make($0, series: "Series \($0 % 100)") }

        // The arrangement `LibraryModel.rebuild()` applies, with the model's own query: the
        // model has no public way to take publications without a folder walk.
        let started = Date()
        let visible = LibraryIndex.arrange(publications, query: model.query, locale: .storyArc)
        let elapsed = Date().timeIntervalSince(started)

        #expect(visible.count == 10_000)
        #expect(elapsed < 1.0, "arranging took \(elapsed)s")
        let groups = LibraryGrid.groupedBySeries(visible)
        #expect(groups.count == 100)
        #expect(groups.allSatisfy { $0.publications.count == 100 })
        #expect(groups.first?.name == "Series 0")
    }

    @Test("A click selects one, Command-click adds and removes, Shift-click extends")
    func selection() {
        let order = (0..<6).map { "p\($0)" }
        var selection = LibrarySelection().clicked("p1")
        #expect(selection.count == 1 && selection.contains("p1"))

        selection = selection.commandClicked("p3")
        #expect(selection.ids == ["p1", "p3"])
        selection = selection.commandClicked("p1")
        #expect(selection.ids == ["p3"])

        selection = selection.shiftClicked("p0", order: order)
        #expect(selection.ids == ["p0", "p1", "p2", "p3"])
        #expect(selection.clicked("p5").ids == ["p5"])
        #expect(selection.kept(in: ["p0", "p9"]).ids == ["p0"])
    }

    @Test("The line under a cover names the series and issue, and never repeats the title")
    func secondLine() {
        #expect(CoverCell.secondLine(of: TestPublications.make(4, series: "Saga")) == "Saga · 4")
        #expect(CoverCell.secondLine(of: TestPublications.make(4)) == nil)
        let guessed = Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/natural-sort.cbz"), format: .cbz,
            displayTitle: "natural-sort", series: "Natural-Sort", origin: .inferred
        )
        #expect(CoverCell.secondLine(of: guessed) == nil)
    }

    @Test("The grid adds columns with the width and never fewer than two")
    func gridColumns() {
        #expect(LibraryGrid.columns(for: 400).count == 2)
        #expect(LibraryGrid.columns(for: 1100).count >= 5)
        #expect(LibraryGrid.columns(for: 1800).count > LibraryGrid.columns(for: 1100).count)
        // The grid keeps its width between steps of a live resize.
        #expect(LibraryGrid.snapped(1105) == LibraryGrid.snapped(1120))
        #expect(LibraryGrid.snapped(1110).truncatingRemainder(dividingBy: LibraryGrid.widthStep) == 0)
        #expect(LibraryGrid.snapped(-5) == 0)
    }
}
