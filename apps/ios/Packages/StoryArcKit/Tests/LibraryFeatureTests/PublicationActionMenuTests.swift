import Foundation
import Testing

@testable import LibraryFeature
import StoryArcCore

/// The one action list a publication offers, wherever it is drawn — the piece this menu
/// decides for itself rather than borrowing from `AddToShelfMenu`: whether there is anything
/// to download or to remove. `PublicationActionsCanCopyTests` below covers the shared rule
/// this now asks, `PublicationActions.canCopy`, which `DetailActions` asks too.
struct PublicationActionMenuTests {

    private func publication(
        format: PublicationFormat = .cbz,
        streaming: StreamingCapability = .streams
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/comics/one.\(format.rawValue)"),
            format: format,
            displayTitle: "One",
            origin: .inferred,
            streaming: streaming
        )
    }

    @Test("A publication no decoder will open cannot be downloaded")
    func refusedPublicationCannotBeDownloaded() {
        let refused = publication(format: .cb7, streaming: .refused)
        #expect(!refused.isOpenable)
        #expect(!PublicationActions.canDownload(refused))
    }

    @Test("A folder of images has nothing a single file could copy")
    func imageFolderCannotBeDownloaded() {
        #expect(!PublicationActions.canDownload(publication(format: .imageFolder)))
    }

    @Test("An ordinary openable publication can be downloaded")
    func ordinaryPublicationCanBeDownloaded() {
        #expect(PublicationActions.canDownload(publication(format: .cbz)))
    }

    @Test("A kept copy offers to remove itself, whatever else is true of it")
    func keptCopyOffersRemoval() {
        #expect(DownloadOffer.of(publication(format: .imageFolder), isKept: true, canCopy: true) == .remove)
        let refused = publication(format: .cb7, streaming: .refused)
        #expect(DownloadOffer.of(refused, isKept: true, canCopy: false) == .remove)
    }

    @Test("A copy that could be fetched and is not kept offers to download")
    func fetchableCopyOffersDownload() {
        #expect(DownloadOffer.of(publication(format: .cbz), isKept: false, canCopy: true) == .download)
    }

    @Test("Nothing that could be fetched offers neither")
    func nothingFetchableOffersNeither() {
        #expect(DownloadOffer.of(publication(format: .imageFolder), isKept: false, canCopy: false) == .none)
        let refused = publication(format: .cb7, streaming: .refused)
        #expect(DownloadOffer.of(refused, isKept: false, canCopy: false) == .none)
    }

    @Test("A row the menu found no route to copy offers no download it cannot deliver")
    func noRouteOffersNoDownload() {
        // The state machine asks only what `PublicationActions.canCopy` already decided —
        // `PublicationActionsCanCopyTests` is where a Kavita chapter, an OPDS row and a
        // local file are told apart.
        #expect(DownloadOffer.of(publication(format: .cbz), isKept: false, canCopy: false) == .none)
    }
}

/// Whether `PublicationActionMenu`'s download action has anywhere to send its copy.
///
/// `PublicationActions.canCopy` is what fixed the menu's own regression: it asked
/// `isLocalFile` where `DetailActions` asked `model.canKeepKavitaChapter(_:)`, so the
/// primary page's menu could keep a browsed Kavita chapter that had never been opened and
/// this one, offering the identical action, could not — `kavita-server`'s *Keeping a
/// chapter on the device* fixed one call site and left the other asking the wrong
/// question. Lifting the rule into one place is what makes that impossible to repeat.
@MainActor
struct PublicationActionsCanCopyTests {
    private func publication(
        remoteID: String,
        format: PublicationFormat = .cbz,
        streaming: StreamingCapability = .streams
    ) -> Publication {
        Publication(
            identity: PublicationIdentity(serverIdentifier: .init(sourceID: UUID(), remoteID: remoteID)),
            format: format,
            displayTitle: "Issue",
            origin: .authoritative,
            streaming: streaming
        )
    }

    /// A model that cannot resolve a Kavita route for anything, whatever this machine's own
    /// keychain and defaults hold — `registry` is empty, and `canKeepKavitaChapter` refuses
    /// before it asks either store. `KavitaKeepRouteTests` proves that refusal directly; this
    /// only needs it to be reliable, not to prove it again.
    private func modelWithNoRegisteredSource() -> LibraryModel {
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [])
        return model
    }

    /// A network share, as `LibraryMerge.location(forNormalizedPath:)` files one: browsed over
    /// `smb://` and identified by that path rather than by any server's own remote id.
    private func shareRow() -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "smb://nas/comics/one.cbz"),
            format: .cbz,
            displayTitle: "One",
            origin: .inferred
        )
    }

    @Test("An OPDS row with no file is not refused for having none")
    func opdsRemoteRowCanCopy() {
        // The regression this proves: an OPDS row's identity never starts with "chapter:", so
        // it takes the queue's own road rather than the Kavita route — which is the road the
        // menu's own `isLocalFile` check used to close.
        let remote = publication(remoteID: "opds:9")
        #expect(PublicationActions.canCopy(remote, file: nil, model: modelWithNoRegisteredSource()))
    }

    @Test("A network share row offers no copy, because its location is not a file to copy")
    func shareRowCannotCopy() {
        // `LibraryModel.keepOffline(_:)` copies the location with `FileManager`, which cannot
        // read an `smb://` URL, and falls through to a queue that has no road for a share
        // either. The menu drew a Download here that reported success and moved nothing.
        let file = URL(string: "smb://nas/comics/one.cbz")
        #expect(!PublicationActions.canCopy(shareRow(), file: file, model: modelWithNoRegisteredSource()))
    }

    @Test("A remote row of a kind no queue serves offers no copy either")
    func unservedRemoteRowCannotCopy() {
        let remote = publication(remoteID: "shelf:9")
        #expect(!PublicationActions.canCopy(remote, file: nil, model: modelWithNoRegisteredSource()))
    }

    @Test("A chapter row with a local file already on this device copies without asking the route")
    func chapterWithLocalFileCanCopy() {
        let chapter = publication(remoteID: "chapter:9")
        let file = URL(fileURLWithPath: "/tmp/one.cbz")
        #expect(PublicationActions.canCopy(chapter, file: file, model: modelWithNoRegisteredSource()))
    }

    @Test("A browsed chapter with no file and no registered source has no route to copy")
    func chapterWithNoFileAndNoRouteCannotCopy() {
        let chapter = publication(remoteID: "chapter:9")
        #expect(!PublicationActions.canCopy(chapter, file: nil, model: modelWithNoRegisteredSource()))
    }

    @Test("A publication no decoder will open cannot be copied, even as a local file")
    func refusedPublicationCannotCopyEvenAsLocalFile() {
        let refused = publication(remoteID: "chapter:9", format: .cb7, streaming: .refused)
        let file = URL(fileURLWithPath: "/tmp/one.cb7")
        #expect(!PublicationActions.canCopy(refused, file: file, model: modelWithNoRegisteredSource()))
    }
}
