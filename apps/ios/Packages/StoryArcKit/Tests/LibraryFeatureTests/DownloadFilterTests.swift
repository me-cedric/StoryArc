import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// What the "Downloaded" facet admits, and what keeps it from being the availability axis
/// under a second name.
///
/// `library-browsing`'s *Filtering offline*: filtering to "Downloaded" shows "only
/// publications readable without a network … regardless of source state". The clause that
/// is easy to break is the second one — a shelf that hides a downloaded chapter because the
/// Kavita server it came from has gone away is exactly the failure the scenario exists to
/// prevent, and it is invisible until someone is on a plane.
///
/// Android's `DownloadFilterTest` asserts these cases one for one.
@Suite("Downloaded filter")
struct DownloadFilterTests {

    // MARK: - Fixtures

    private func publication(_ name: String, sourceID: UUID? = nil) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/fixtures/\(name).cbz"),
            format: .cbz,
            displayTitle: name,
            origin: .inferred,
            sourceID: sourceID
        )
    }

    // MARK: - The rule

    @Test("Either way keeps a publication whether or not the app fetched it")
    func eitherKeepsEverything() {
        #expect(DownloadFilter.either.keeps(isDownloaded: true))
        #expect(DownloadFilter.either.keeps(isDownloaded: false))
    }

    @Test("Downloaded keeps only what the app fetched and is keeping")
    func downloadedKeepsOnlyTheAppsOwnCopies() {
        #expect(DownloadFilter.downloaded.keeps(isDownloaded: true))
        #expect(!DownloadFilter.downloaded.keeps(isDownloaded: false))
    }

    @Test("Not downloaded is the question before a journey, and keeps the rest")
    func notDownloadedKeepsTheRest() {
        #expect(!DownloadFilter.notDownloaded.keeps(isDownloaded: true))
        #expect(DownloadFilter.notDownloaded.keeps(isDownloaded: false))
    }

    @Test("Only the two narrowing answers count towards the badge")
    func onlyNarrowingAnswersAreActive() {
        #expect(!DownloadFilter.either.isActive)
        #expect(DownloadFilter.downloaded.isActive)
        #expect(DownloadFilter.notDownloaded.isActive)
    }

    // MARK: - The shelf

    @Test("A downloaded publication survives however its source is doing")
    func sourceStateIsNotConsulted() {
        // The whole point of the scenario: a chapter fetched from a server that has since
        // gone away is still readable, so it is still on the shelf. The rule never asks the
        // registry, and this is what says so.
        let fromAwayServer = publication("Nightjar 1", sourceID: UUID())
        let kept = DownloadFilter.downloaded.narrow([fromAwayServer]) { _ in true }
        #expect(kept.map(\.displayTitle) == ["Nightjar 1"])
    }

    @Test("A file a folder scan found is on the device and is not downloaded")
    func aScannedFileIsNotADownload() {
        // The line the availability axis does not draw. `LibraryAvailability.onThisDevice`
        // keeps this file — it opens with no network — and this group does not, because the
        // app never fetched it and the card it sits on can be pulled.
        let scanned = publication("Ashfall 1")
        let downloaded = publication("Ashfall 2")
        let isDownloaded: (Publication) -> Bool = { $0.displayTitle == "Ashfall 2" }

        #expect(
            DownloadFilter.downloaded.narrow([scanned, downloaded], isDownloaded: isDownloaded)
                .map(\.displayTitle) == ["Ashfall 2"]
        )
        #expect(
            DownloadFilter.notDownloaded.narrow([scanned, downloaded], isDownloaded: isDownloaded)
                .map(\.displayTitle) == ["Ashfall 1"]
        )
    }

    @Test("Either way hands the shelf back untouched, in the order it arrived")
    func eitherPreservesTheOrder() {
        let shelf = [publication("C"), publication("A"), publication("B")]
        let kept = DownloadFilter.either.narrow(shelf) { _ in false }
        #expect(kept.map(\.displayTitle) == ["C", "A", "B"])
    }

    @Test("Narrowing keeps the order the sort put the shelf in")
    func narrowingIsStable() {
        // One pass over an already-sorted list. A group that re-sorted would reshuffle the
        // shelf under a reader who only ticked a box.
        let shelf = [publication("C"), publication("A"), publication("B")]
        let kept = DownloadFilter.downloaded.narrow(shelf) { $0.displayTitle != "A" }
        #expect(kept.map(\.displayTitle) == ["C", "B"])
    }

    @Test("The stored value is a name, so a reordered enum cannot change what it means")
    func storedByName() {
        #expect(DownloadFilter.either.rawValue == "either")
        #expect(DownloadFilter.downloaded.rawValue == "downloaded")
        #expect(DownloadFilter.notDownloaded.rawValue == "notDownloaded")
        #expect(DownloadFilter.storageKey == "app.storyarc.libraryDownloadFilter")
    }

    @Test("A reader who has never chosen gets the whole shelf")
    func defaultIsEither() {
        // A first launch that opened on "Downloaded" would show an empty shelf to a reader
        // who had just added a folder full of comics.
        #expect(DownloadFilter.allCases.first == .either)
        #expect(DownloadFilter(rawValue: "") == nil)
    }
}
