import Catalogue
import Foundation
import Persistence
import StoryArcCore
import Testing

@testable import LibraryFeature

/// 11.9: `CertificatePins.forget` and `CertificatePinStore.forget` are documented as "Called
/// when its source is removed", and nothing called either of them — removing a pinned
/// catalogue or Kavita server left its pin live for whatever reader or server next answered
/// at that host. Android's `SourcePinForgettingTest` asserts the same two cases.
@Suite("A removed source's pin")
@MainActor
struct SourcePinForgettingTests {
    private let host = "books.example"
    private let fingerprint = "6B:D2:93"

    private func pinStore() -> CertificatePinStore {
        CertificatePinStore(defaults: UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)") ?? .standard)
    }

    private func catalogue(locator: String = "https://books.example/feed") -> Source {
        Source(displayName: "Library", kind: .opdsCatalog, locator: locator)
    }

    @Test("Removing a source's only catalogue at a host forgets its pin")
    func removingTheOnlySourceAtAHostForgetsIt() {
        let model = LibraryModel()
        let source = catalogue()
        model.add(source)
        let pins = CertificatePins([host: [fingerprint]])
        let store = pinStore()
        store.save(pins.all)

        model.remove(source, credentials: nil, pins: pins, pinStore: store)

        #expect(!pins.accepts(fingerprint, from: host))
        #expect(store.pins()[host] == nil)
    }

    @Test("A pin stays while another saved source answers at the same host")
    func aSharedHostKeepsItsPin() {
        let model = LibraryModel()
        let removed = catalogue()
        let kept = Source(displayName: "Kavita", kind: .kavitaServer, locator: "https://\(host)")
        model.add(removed)
        model.add(kept)
        let pins = CertificatePins([host: [fingerprint]])
        let store = pinStore()
        store.save(pins.all)

        model.remove(removed, credentials: nil, pins: pins, pinStore: store)

        #expect(pins.accepts(fingerprint, from: host))
        #expect(store.pins()[host] == [fingerprint])
    }
}
