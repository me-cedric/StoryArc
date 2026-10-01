import Foundation
import Testing

@testable import Persistence

/// 11.2: a pin accepted on one screen must not erase a pin accepted on another.
@Suite("Certificate pin store")
struct CertificatePinStoreTests {

    private func store() -> CertificatePinStore {
        let defaults = UserDefaults(suiteName: "app.storyarc.tests.\(UUID().uuidString)")
        return CertificatePinStore(defaults: defaults ?? .standard)
    }

    @Test("A new pin keeps every pin already on disk")
    func aNewPinKeepsEveryStoredPin() {
        let store = store()
        store.save(["library.example": ["AA:01"]])

        store.pin("BB:02", for: "home.example")
        store.pin("CC:03", for: "library.example")

        #expect(store.pins() == ["library.example": ["AA:01", "CC:03"], "home.example": ["BB:02"]])
    }
}
