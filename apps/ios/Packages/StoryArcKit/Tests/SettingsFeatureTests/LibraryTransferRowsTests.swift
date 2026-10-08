import Foundation
import Testing

@testable import Persistence
@testable import SettingsFeature
import StoryArcCore

/// `library-portability` tasks 2.5 and 3.1: Sources offers the two rows that move a library, and
/// only where there are stores behind them. Android's `SourcesGroupTransferRowsTest` asserts the
/// same rows.
@MainActor
@Suite("Sources offers export and import")
struct LibraryTransferRowsTests {

    private func sources(transfer: LibraryTransfer?) -> SourcesSettings {
        SourcesSettings(
            sources: [],
            itemCount: { _ in 0 },
            isPartial: { _ in false },
            onRemove: { _ in },
            onRename: { _, _ in },
            libraryTransfer: transfer
        )
    }

    @Test("With stores behind it the group draws the transfer section")
    func theSectionIsDrawn() throws {
        let device = try TransferDevice()

        let sections = values(of: LibraryTransferSection.self, in: sources(transfer: device.transfer))

        // An optional section is found as itself and as what it wraps, so it is counted, not equal.
        #expect(!sections.isEmpty)
    }

    @Test("With none the two rows are not drawn")
    func noStoresNoRows() {
        #expect(values(of: LibraryTransferSection.self, in: sources(transfer: nil)).isEmpty)
    }

    @Test("The section is the two rows and a sentence about what they move")
    func theSectionHoldsTwoRowsAndAFooter() throws {
        let device = try TransferDevice()
        let section = LibraryTransferSection(transfer: device.transfer, highlight: nil) { _ in }

        let keys = lookups(in: section)

        #expect(keys.isSuperset(of: ["transfer.export", "transfer.import", "transfer.section.footer"]))
    }
}
