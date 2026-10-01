import Foundation
import Testing

import Catalogue
@testable import LibraryFeature

/// Finding, in a freshly read feed, the entry a catalogue-only row names.
///
/// `collections-and-reading-lists`' bulk download "queues them per offline-downloads" for
/// a member with no local file — a unified-shelf row `OpdsContributor` built with no
/// acquisition URL kept on it. This pins the matching `KeepOffline.enqueueRemote` does the
/// fetch around. Android asserts the same cases in `RemoteMemberResolutionTest`.
@Suite("Resolving a catalogue-only member against a freshly read feed")
struct RemoteMemberResolutionTests {

    private func acquisition(_ href: String, mediaType: String = "application/epub+zip") -> OpdsAcquisition {
        OpdsAcquisition(
            href: URL(string: href) ?? URL(fileURLWithPath: "/"),
            mediaType: mediaType,
            kind: .open
        )
    }

    @Test("An OPDS remote id finds its entry and the best acquisition")
    func opdsIDFindsItsEntry() {
        let entry = OpdsEntry(
            id: "hl09", title: "Harbour Lights 09",
            acquisitions: [acquisition("https://library.example/hl09.epub")]
        )
        let feed = OpdsFeed(title: "Library", publications: [entry])

        let found = RemoteMemberResolution.opdsEntry(matching: "opds:hl09", in: feed)

        #expect(found?.0.id == "hl09")
        #expect(found?.1.href.absoluteString == "https://library.example/hl09.epub")
    }

    @Test("A Kavita chapter's remote id is not an OPDS one")
    func kavitaIDIsNotMatched() {
        // "aaaaa" is five characters, the same length as "opds:" — a prefix check dropped
        // in favour of a bare `dropFirst(5)` would still land on this real entry id and
        // match it, which is exactly the failure this pins.
        let entry = OpdsEntry(
            id: "entry9", title: "Chapter 9",
            acquisitions: [acquisition("https://library.example/9.epub")]
        )
        let feed = OpdsFeed(title: "Library", publications: [entry])

        #expect(RemoteMemberResolution.opdsEntry(matching: "aaaaaentry9", in: feed) == nil)
    }

    @Test("An entry a later feed no longer lists resolves to nothing")
    func anEntryTheFeedNoLongerListsIsNil() {
        let feed = OpdsFeed(title: "Library", publications: [])

        #expect(RemoteMemberResolution.opdsEntry(matching: "opds:hl09", in: feed) == nil)
    }

    @Test("The id matched is the one named, not merely the first on the page")
    func theIDNamedIsMatchedRatherThanTheFirstOnThePage() {
        let wanted = OpdsEntry(
            id: "hl09", title: "Harbour Lights 09",
            acquisitions: [acquisition("https://library.example/hl09.epub")]
        )
        let other = OpdsEntry(
            id: "hl08", title: "Harbour Lights 08",
            acquisitions: [acquisition("https://library.example/hl08.epub")]
        )
        let feed = OpdsFeed(title: "Library", publications: [other, wanted])

        let found = RemoteMemberResolution.opdsEntry(matching: "opds:hl09", in: feed)

        #expect(found?.0.id == "hl09")
    }

    @Test("An entry with nothing this app can open resolves to nothing")
    func anEntryWithNoReadableAcquisitionIsNil() {
        let entry = OpdsEntry(
            id: "hl09",
            title: "Harbour Lights 09",
            acquisitions: [
                OpdsAcquisition(
                    href: URL(fileURLWithPath: "/hl09.cb7"),
                    mediaType: "application/x-7z-compressed",
                    kind: .open
                ),
            ]
        )
        let feed = OpdsFeed(title: "Library", publications: [entry])

        #expect(RemoteMemberResolution.opdsEntry(matching: "opds:hl09", in: feed) == nil)
    }

    @Test("The best acquisition is picked, the same way the catalogue page would")
    func theBestAcquisitionIsPicked() {
        let entry = OpdsEntry(
            id: "hl09",
            title: "Harbour Lights 09",
            acquisitions: [
                acquisition("https://library.example/hl09.cbz", mediaType: "application/vnd.comicbook+zip"),
                acquisition("https://library.example/hl09.epub", mediaType: "application/epub+zip"),
            ]
        )
        let feed = OpdsFeed(title: "Library", publications: [entry])

        let found = RemoteMemberResolution.opdsEntry(matching: "opds:hl09", in: feed)

        #expect(found?.1.href.absoluteString == "https://library.example/hl09.epub")
    }
}
