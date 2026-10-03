import SwiftUI
import Testing

@testable import LibraryFeature
import StoryArcCore

/// Task 19.6: the library "does not fall back to a list at accessibility text sizes" — the
/// grid stayed a grid, however wide its captions had wrapped. `libraryFallsBackToList` is
/// the whole rule, asked without composing a shelf. Android asserts the same answer by
/// composing `LibraryScreen` in `LibraryListFallbackTest.kt`, because Robolectric lets it
/// draw what iOS can only compute on a host.
@Suite("The library's list fallback")
struct LibraryListFallbackTests {

    @Test("A reader who stored Grid keeps it at an ordinary text size")
    func gridStaysGridOrdinarily() {
        #expect(!libraryFallsBackToList(stored: .grid, textSize: .large))
    }

    @Test("A reader who stored Grid still gets List at the smallest accessibility size")
    func gridFallsBackAtTheSmallestAccessibilitySize() {
        #expect(libraryFallsBackToList(stored: .grid, textSize: .accessibility1))
    }

    @Test("A reader who stored Grid still gets List at the largest accessibility size")
    func gridFallsBackAtTheLargestAccessibilitySize() {
        #expect(libraryFallsBackToList(stored: .grid, textSize: .accessibility5))
    }

    @Test("A reader who stored List keeps List at an ordinary text size — nothing changes underneath them")
    func listStaysListOrdinarily() {
        #expect(libraryFallsBackToList(stored: .list, textSize: .large))
    }

    @Test("The largest size that is not yet an accessibility size does not fall back")
    func largestOrdinarySizeDoesNotFallBack() {
        #expect(!libraryFallsBackToList(stored: .grid, textSize: .xxxLarge))
    }
}
