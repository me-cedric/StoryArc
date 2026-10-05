import Foundation
@testable import LibraryFeature
import Persistence
import StoryArcCore
import Testing

/// A share and a catalogue resume their continuation after a relaunch, which only a Kavita
/// server could do before.
///
/// `sources`' *More from a source than the library holds* asks a read to keep going until the
/// library holds all of it, and a relaunch is the common case on a phone. Only Kavita wrote
/// its progress, so the resume branch `adoptPartialSources` holds was dead for the other two
/// kinds. Neither continues by a page number, so the cursor has to be written with the count
/// or the restored record says where the read stood without saying what to ask for next.
/// Android's `ContinuedReadCursorSurvivesRelaunchTest` is the twin.
@MainActor
@Suite("A continued read's cursor survives a relaunch")
struct ContinuedReadCursorSurvivesRelaunchTests {

    private let sourceID = UUID()
    private let store = SourceReadProgressStore()

    private func model(kind: SourceKind) -> LibraryModel {
        let model = LibraryModel()
        model.registry = SourceRegistry(sources: [Source(id: sourceID, displayName: "Attic", kind: kind)])
        return model
    }

    @Test("A share resumes the frontier it stopped at, not only the count it had reached")
    func shareResumesItsFrontier() {
        defer { store.clear(for: sourceID) }
        store.record(StoredSourceProgress(read: 540, nextPage: 4, smbQueue: ["d40", "d41"]), for: sourceID)

        let model = model(kind: .networkShare)
        model.adoptPartialSources(.init(partial: [sourceID]))

        #expect(model.partialSources[sourceID] == SourceReadProgress(read: 540, total: nil, nextPage: 4))
        #expect(model.smbQueues[sourceID] == ["d40", "d41"])
    }

    @Test("A catalogue resumes the link it stopped at, in preference to its first page's own")
    func catalogueResumesItsLink() throws {
        defer { store.clear(for: sourceID) }
        let stopped = URL(string: "https://library.example/feed?page=7")
        store.record(StoredSourceProgress(read: 180, nextPage: 7, opdsNext: stopped), for: sourceID)

        let model = model(kind: .opdsCatalog)
        // The root feed this launch just read hands back page two, as every pull does: it has
        // never heard of the six pages a previous launch already merged.
        let firstPage = try #require(URL(string: "https://library.example/feed?page=2"))
        model.adoptPartialSources(.init(partial: [sourceID], opdsNext: [sourceID: firstPage]))

        #expect(model.partialSources[sourceID] == SourceReadProgress(read: 180, total: nil, nextPage: 7))
        #expect(model.opdsNext[sourceID] == stopped)
    }

    @Test("A landed continuation page writes its cursor to disk beside its count")
    func landingWritesTheCursor() {
        defer { store.clear(for: sourceID) }
        let model = model(kind: .networkShare)
        model.partialSources[sourceID] = SourceReadProgress(read: 200, total: nil, nextPage: 2)
        // `readSourceOnward` advances the cursor before it lands the page, so this is what
        // the dictionary holds by the time `landContinuedSlice` runs.
        model.smbQueues[sourceID] = ["d40", "d41"]

        model.landContinuedSlice(
            source: sourceID,
            slice: SourceSlice(publications: [], holdsMore: true),
            step: .continuing(SourceReadProgress(read: 540, total: nil, nextPage: 3))
        )

        #expect(
            store.progress(for: sourceID)
                == StoredSourceProgress(read: 540, nextPage: 3, smbQueue: ["d40", "d41"])
        )
    }

    @Test("A finished continuation forgets its cursor along with its count")
    func finishingForgetsTheCursor() {
        defer { store.clear(for: sourceID) }
        let model = model(kind: .networkShare)
        model.partialSources[sourceID] = SourceReadProgress(read: 200, total: nil, nextPage: 2)
        model.smbQueues[sourceID] = ["d40"]

        model.landContinuedSlice(
            source: sourceID,
            slice: SourceSlice(publications: [], holdsMore: false),
            step: .finished(SourceReadProgress(read: 210, total: nil, nextPage: 3))
        )

        #expect(store.progress(for: sourceID) == nil)
    }
}
