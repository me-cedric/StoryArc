import Foundation
import Testing

import StoryArcCore

@testable import LibraryFeature

/// What a shelf's download confirmation counts.
///
/// `collections-and-reading-lists` has the app state "the item count and total size before
/// starting". It counted every member this device did not already hold, and
/// ``LibraryModel/keepOffline(_:queue:)`` then copied fewer: a folder of images has no single
/// file to take, a publication no decoder opens has nothing worth fetching, and a network
/// share row has no road at all. The reader was told a number and a size that the action did
/// not deliver, and was told nothing about the difference.
@Suite("What a shelf download counts")
struct ShelfDownloadCountTests {

    private func publication(
        id path: String,
        format: PublicationFormat = .cbz
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: path),
            format: format,
            displayTitle: path,
            origin: .inferred
        )
    }

    /// A network share, as `LibraryMerge.location(forNormalizedPath:)` files one.
    private func shareRow() -> Publication {
        publication(id: "smb://nas/comics/one.cbz")
    }

    @Test("A member the rule refuses is left out of the count")
    func arefusedMemberIsNotCounted() {
        let kept = publication(id: "/comics/one.cbz")
        let refused = publication(id: "/comics/two.cbz")

        let wanted = downloadableMembers(
            [kept.id, refused.id],
            among: [kept, refused]
        ) { $0.id == kept.id }

        #expect(wanted == [kept.id])
    }

    @Test("A member the shelf names and the library no longer holds is left out")
    func aVanishedMemberIsNotCounted() {
        let held = publication(id: "/comics/one.cbz")

        let wanted = downloadableMembers([held.id, "/comics/gone.cbz"], among: [held]) { _ in true }

        #expect(wanted == [held.id])
    }

    /// The real rule, not a stub: the three kinds of member the count used to overstate, asked
    /// of ``PublicationActions/canCopy(_:file:model:)`` itself.
    @Test("A folder of images is out; an ordinary comic and a share row are in")
    @MainActor
    func theCountIsWhatOneTapWouldCopy() {
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [])
        let comic = publication(id: "/comics/one.cbz")
        let folder = publication(id: "/comics/loose", format: .imageFolder)
        let share = shareRow()
        let members: Set<String> = [comic.id, folder.id, share.id]
        // Every one of them has a location the library can place, which is what makes the
        // refusals here about the member and not about a missing file.
        let locations: [String: URL] = [
            comic.id: URL(fileURLWithPath: "/comics/one.cbz"),
            folder.id: URL(fileURLWithPath: "/comics/loose"),
            share.id: URL(string: "smb://nas/comics/one.cbz") ?? URL(fileURLWithPath: "/"),
        ]

        let wanted = downloadableMembers(members, among: [comic, folder, share]) {
            PublicationActions.canCopy($0, file: locations[$0.id], model: model)
        }

        #expect(
            wanted == [comic.id, share.id],
            "The confirmation states a count the download does not copy."
        )
    }

    /// Task 7.7's second half, from the side the first half could not state.
    ///
    /// Wave 8 narrowed the stated count to what one tap copies, and a share member was out of
    /// it because ``LibraryModel/keepOffline(_:queue:)`` had no road for one. It has the
    /// chunked copy now, so the member belongs in the count again — and this fails if the road
    /// is taken away without the count being narrowed with it.
    @Test("A share row is a member a bulk download now copies")
    @MainActor
    func aShareMemberIsCounted() {
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [])
        let address = URL(string: "smb://nas/comics/one.cbz") ?? URL(fileURLWithPath: "/")

        #expect(
            PublicationActions.canCopy(shareRow(), file: address, model: model),
            "A share member is skipped silently again — task 7.7's own defect."
        )
    }

    @Test("The confirmation is built from the counted members, not from every member")
    func theConfirmationAsksForTheCountedSet() {
        let actions = LibraryFeatureSource.code(of: "Sources/LibraryFeature/ShelfBulkActions.swift")

        #expect(actions.contains("let wanted = downloadableMembers(members, among: model.publications)"))
        #expect(actions.contains("BulkDownloadAsk.of(wanted, onDevice: model.keptOffline)"))
    }
}
