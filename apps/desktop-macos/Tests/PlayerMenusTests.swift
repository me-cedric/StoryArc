import Foundation
import Playback
import Testing

@testable import StoryArc

/// The chapter rows and the sleep timer's clock (`audio-playback`, *Chapters*, *Sleep timer*).
@MainActor
@Suite("Player menus")
struct PlayerMenusTests {
    @Test("A chapter ahead states its length, the one in progress what is left, a heard one its length")
    func chapterRows() {
        let part = PlaybackPart(index: 2, title: "Three", duration: 760)
        #expect(ChaptersMenu.row(part, mark: .unplayed, offset: 0) == "Three · 12:40")
        #expect(ChaptersMenu.row(part, mark: .inProgress, offset: 510).hasPrefix("Three · 4:10"))
        #expect(ChaptersMenu.row(part, mark: .finished, offset: 0) == "Three · 12:40")
    }

    @Test("The sleep clock reads minutes and seconds and never goes below zero")
    func clock() {
        #expect(SleepMenu.clock(300) == "5:00")
        #expect(SleepMenu.clock(-4) == "0:00")
    }
}
