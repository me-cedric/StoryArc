import Testing

@testable import StoryArc

/// Moving a source up or down in the registry's insertion terms (`sources`, *Reordering sources*).
@Suite("Source order")
struct SourceOrderTests {
    @Test("The first source cannot move up and the last cannot move down; the rest move by one place")
    func moves() {
        #expect(SourceOrder.up(from: 0) == nil)
        #expect(SourceOrder.up(from: 2) == 1)
        #expect(SourceOrder.down(from: 2, count: 3) == nil)
        #expect(SourceOrder.down(from: 0, count: 3) == 2)
    }
}
