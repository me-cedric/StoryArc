import Foundation
import Testing

@testable import LibraryFeature
import Persistence
import StoryArcCore

/// How many marks one cover is allowed to carry, and which one gives when a third arrives.
///
/// `library-browsing` lets a cover carry "at most two marks: how far the reader has got, and
/// whether it can be read with no network", and adds that "no third mark is added to a cover
/// for any reason". Selection is where that cap was broken: a picked cover drew a tick, a
/// progress rail and a downloaded mark at once. The rule is that the pick mark substitutes
/// into the pair rather than being added to it, and this is the case that says so.
@Suite("Cover cell marks")
@MainActor
struct CoverCellMarksTests {

    /// A library holding one downloaded publication, so the mark's own condition is true.
    private struct Shelf {
        let model: LibraryModel
        let publication: Publication
        /// The throwaway directory standing in for the app's own download store.
        let directory: URL
    }

    private func downloaded() throws -> Shelf {
        let downloads = URL.temporaryDirectory.appending(path: "downloads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let file = downloads.appending(path: "kept.cbz")
        let publication = Publication(
            identity: PublicationIdentity(normalizedPath: file.path),
            format: .cbz,
            displayTitle: "Fixture",
            origin: .inferred
        )
        let model = LibraryModel(downloadStore: DownloadStore(directory: downloads))
        model.publications = [publication]
        model.locations[publication.id] = file
        return Shelf(model: model, publication: publication, directory: downloads)
    }

    private func cell(
        _ model: LibraryModel,
        _ publication: Publication,
        picked: Bool?
    ) -> CoverCell {
        CoverCell(
            publication: publication,
            model: model,
            maxPixelSize: 200,
            isPicked: picked
        )
    }

    @Test("A downloaded cover carries the mark while the reader is browsing")
    func browsingShowsTheMark() throws {
        let shelf = try downloaded()
        defer { try? FileManager.default.removeItem(at: shelf.directory) }

        #expect(cell(shelf.model, shelf.publication, picked: nil).showsOnDeviceMark)
    }

    @Test("The same cover drops it while the reader is picking")
    func pickingHidesTheMark() throws {
        let shelf = try downloaded()
        defer { try? FileManager.default.removeItem(at: shelf.directory) }

        // Both states of the pick mark, because it is the *mode* that spends the budget,
        // not the answer: an unpicked cover in selection mode still draws the empty circle.
        #expect(!cell(shelf.model, shelf.publication, picked: false).showsOnDeviceMark)
        #expect(!cell(shelf.model, shelf.publication, picked: true).showsOnDeviceMark)
    }
}
