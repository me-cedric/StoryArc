import SwiftUI
import Testing

@testable import LibraryFeature

/// A well with no artwork in it sets the title at the reader's size, or not at all.
///
/// The rule replaces a `minimumScaleFactor(0.6)` that stood in two wells — the grid's cell
/// and Home's shelf card — and that Apple's own accessibility audit reported as
/// `Dynamic Type font sizes are partially unsupported`. It could only ever have been found
/// by an audit or by a booted simulator at the largest text size: a scale factor is
/// invisible in code review and invisible in a `#Preview` at the default setting, and it
/// shrinks the reader's chosen size hardest for the reader who chose the largest.
///
/// Asserted here rather than in a view because the whole substance of it is one decision
/// over one input, and a view is where that decision cannot be reached.
@Suite("Coverless well")
struct CoverlessWellTests {

    /// Every size the reader can choose that is not an accessibility size.
    private static let ordinarySizes: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
    ]

    private static let accessibilitySizes: [DynamicTypeSize] = [
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
    ]

    @Test(
        "The stand-in title is drawn at every ordinary text size",
        arguments: ordinarySizes
    )
    func theTitleStandsInAtOrdinarySizes(size: DynamicTypeSize) {
        // What the well is for: a shelf of coverless EPUBs is otherwise a wall of grey
        // cards whose only distinguishing mark is the format they all share.
        #expect(coverlessWellDrawsTitle(at: size))
    }

    @Test(
        "It stands down once the reader is at an accessibility text size",
        arguments: accessibilitySizes
    )
    func theTitleStandsDownAtAccessibilitySizes(size: DynamicTypeSize) {
        // Not shrunk to fit — `design.md` §3 says the token sizes are "the size at the
        // default setting, not a fixed size", and a scale factor is a fixed size in
        // disguise. At these sizes a `headline` in a 146 pt well holds part of one word,
        // which identifies nothing, and the caption directly below the well states the
        // same title in full at the size the reader actually asked for.
        #expect(!coverlessWellDrawsTitle(at: size))
    }

    /// The switch happens exactly once, and in the direction that keeps the title for as
    /// long as it can be read. A rule that flickered back on at a larger size would be a
    /// rule nobody could hold in their head.
    @Test("The title is never brought back by asking for larger text")
    func theRuleIsMonotonic() {
        let ascending = Self.ordinarySizes + Self.accessibilitySizes
        var hasStoodDown = false
        for size in ascending {
            let draws = coverlessWellDrawsTitle(at: size)
            if hasStoodDown { #expect(!draws) }
            if !draws { hasStoodDown = true }
        }
        #expect(hasStoodDown)
    }
}
