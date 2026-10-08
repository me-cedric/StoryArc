import Foundation
import SwiftUI
import Testing

import DesignSystem
@testable import LibraryFeature
import Playback
import StoryArcCore

/// Task 24.3 of `close-the-audited-gaps`: every control has a hit region of 44 × 44 pt.
///
/// `ImageRenderer` lays a view out on the host, so these measure what the production views
/// draw rather than a constant. A frame that is outside a `Button` would pass the same
/// measurement and fail on a device, which is why the modifier sits on the label, and why
/// `AccessibilityAuditTests` asks the platform's own hit-region audit as well.
@Suite("Hit regions of 44 by 44 points")
@MainActor
struct HitRegionTests {

    private func size(of content: some View, width: CGFloat? = nil) -> CGSize {
        let renderer = ImageRenderer(content: content.frame(width: width))
        var measured = CGSize.zero
        renderer.render { size, _ in measured = size }
        return measured
    }

    @Test("A label given a hit region is at least 44 by 44")
    func theModifier() {
        let measured = size(of: Text(verbatim: "OK").hitRegion())

        #expect(measured.width >= 44)
        #expect(measured.height >= 44)
    }

    @Test("The edit button on a cover is a 44 point circle")
    func theEditButton() {
        let menu = CoverMenu(hasCover: true, rows: [[.choose]], act: { _ in })

        let measured = size(of: CoverEditButton(menu: menu))

        #expect(measured.width == 44)
        #expect(measured.height == 44)
    }

    @Test("Each way into a source's own browser is a row of its own, 44 high")
    func moreFromTheLibraryRows() {
        func source(_ name: String) -> Source {
            Source(displayName: name, kind: .kavitaServer, locator: "https://x.invalid")
        }
        func height(_ sources: [Source]) -> CGFloat {
            size(
                of: MoreFromTheLibrary(sources: sources, isPartial: { _ in true }, onBrowse: { _ in }),
                width: 320
            ).height
        }

        let one = height([source("A")])
        let two = height([source("A"), source("B")])

        #expect(two - one >= 44, "The second row added \(two - one) points. A finger needs 44.")
    }

    @Test("Each chapter on the page is a row 44 high, spaced from the next")
    func chapterRows() {
        func chapters(_ count: Int) -> [DetailChapter] {
            (0..<count).map {
                DetailChapter(index: $0, name: .given("Chapter \($0)"), duration: 60, mark: .unplayed, remaining: nil)
            }
        }
        func height(_ count: Int) -> CGFloat {
            size(of: DetailChapterList(chapters: chapters(count), onChoose: { _ in }), width: 320).height
        }

        let delta = height(3) - height(2)

        #expect(delta >= 44 + StoryArcSpace.sm, "A chapter row added \(delta) points.")
    }

    @Test("The A to Z rail is one region at least 44 wide that holds every letter")
    func theRail() {
        let entries = "ABCDEFGHIJKLMNOPQRSTUVWXYZ#".map { RailEntry(label: String($0), publicationID: String($0)) }

        let measured = size(of: RailLetters(shown: entries))

        #expect(measured.width >= 44, "The rail is \(measured.width) points wide. A finger needs 44.")
        #expect(measured.height >= CGFloat(entries.count) * LibraryRail.entryHeight, "Every letter is drawn.")
        #expect(IndexRail.width >= 44, "The shelf reserves the room the rail takes.")
    }
}
