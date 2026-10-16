import Testing

@testable import StoryArc

/// The power assertion of task 2.22: created when a reader is in front, released when the
/// reason ends, silent when the system refuses.
@MainActor
@Suite("Display awake")
struct DisplayAwakeTests {
    private final class Spy: PowerAssertions, @unchecked Sendable {
        var created: [String] = []
        var released: [UInt32] = []
        var refuses = false
        private var next: UInt32 = 41

        func createDisplayAssertion(reason: String) -> UInt32? {
            guard !refuses else { return nil }
            created.append(reason)
            next += 1
            return next
        }

        func release(_ id: UInt32) { released.append(id) }
    }

    @Test("One assertion while any reader is in front, released when the last one leaves")
    func heldAndReleased() {
        let spy = Spy()
        let awake = DisplayAwake(system: spy)

        awake.hold(for: "saga")
        awake.hold(for: "monstress")
        #expect(spy.created == [DisplayAwake.reason])
        #expect(awake.isHeld)

        awake.release(for: "saga")
        #expect(spy.released.isEmpty)
        awake.release(for: "monstress")
        #expect(spy.released == [42])
        #expect(!awake.isHeld)
    }

    @Test("A refusal is silent: nothing is held, nothing is released, nothing is thrown")
    func refusalIsSilent() {
        let spy = Spy()
        spy.refuses = true
        let awake = DisplayAwake(system: spy)

        awake.hold(for: "saga")
        awake.release(for: "saga")

        #expect(!awake.isHeld)
        #expect(awake.refusals == 1)
        #expect(spy.released.isEmpty)
    }

    @Test("Releasing a window that never held does nothing")
    func releaseWithoutHold() {
        let spy = Spy()
        let awake = DisplayAwake(system: spy)
        awake.release(for: "nobody")
        #expect(spy.released.isEmpty)
    }
}
