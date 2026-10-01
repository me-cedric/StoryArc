import SwiftUI
import Testing

import StoryArcCore
@testable import LibraryFeature

/// Task 15.6: "%d of %d entries" had no plural form, so a one-entry list read
/// "1 of 1 entries". The total, not the copying count, is what names the noun: a server
/// that holds everything but one still has several "entries" in the sentence.
@MainActor
@Suite("Promote-entries wording")
struct PromoteEntriesTextTests {
    private func promotion(copying: Int, leftBehind: Int) -> ListPromotion {
        ListPromotion(
            entries: (0..<(copying + leftBehind)).map { "\($0)" },
            heldByServer: { (Int($0) ?? 0) < copying }
        )
    }

    @Test("A total of one reads the singular, whatever the resolves state")
    func totalOfOneIsSingular() {
        let text = promoteEntriesText(promotion(copying: 1, leftBehind: 0))
        let rendered = String(describing: text)
        #expect(!rendered.contains("1 entries"), "read the plural for a total of one: \(rendered)")
    }

    @Test("A total of several reads the plural key, not the singular one")
    func totalOfSeveralIsPlural() {
        let text = promoteEntriesText(promotion(copying: 2, leftBehind: 1))
        let rendered = String(describing: text)
        #expect(!rendered.contains("entries.one"), "used the singular key for a total of 3: \(rendered)")
    }
}
