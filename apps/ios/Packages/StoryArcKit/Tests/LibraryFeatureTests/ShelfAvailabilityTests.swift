import Testing

@testable import LibraryFeature
import StoryArcCore

/// How much of a shelf is already here, pinned apart from any view that draws it.
///
/// `collections-and-reading-lists`' bulk download states a count and a size before it
/// starts; the collection, list and series headers state the same question the other way,
/// up front. Android asserts the same cases in `ShelfAvailabilityTest`.
@Suite("How many of a shelf's members are on this device")
struct ShelfAvailabilityTests {

    private func publication(_ id: String) -> Publication {
        Publication(
            identity: PublicationIdentity(normalizedPath: "/\(id).cbz"),
            format: .cbz,
            displayTitle: id,
            origin: .inferred
        )
    }

    @Test("Every member on this device counts both the same")
    func everyMemberOnDevice() {
        let members = ["a", "b", "c"].map(publication)
        let counted = ShelfAvailability.onDeviceCount(of: members) { _ in true }
        #expect(counted.onDevice == 3)
        #expect(counted.total == 3)
    }

    @Test("No member on this device counts zero of the whole")
    func noMemberOnDevice() {
        let members = ["a", "b"].map(publication)
        let counted = ShelfAvailability.onDeviceCount(of: members) { _ in false }
        #expect(counted.onDevice == 0)
        #expect(counted.total == 2)
    }

    @Test("A mixed shelf counts only the members the predicate accepts")
    func aMixedShelf() {
        let members = ["a", "b", "c", "d"].map(publication)
        let here: Set<String> = [members[0].id, members[2].id]
        let counted = ShelfAvailability.onDeviceCount(of: members) { here.contains($0.id) }
        #expect(counted.onDevice == 2)
        #expect(counted.total == 4)
    }

    @Test("An empty shelf is zero of zero")
    func anEmptyShelf() {
        let counted = ShelfAvailability.onDeviceCount(of: []) { _ in true }
        #expect(counted.onDevice == 0)
        #expect(counted.total == 0)
    }
}
