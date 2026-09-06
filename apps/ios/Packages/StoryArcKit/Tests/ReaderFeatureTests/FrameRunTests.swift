import Testing

@testable import ReaderFeature

/// That the instrument counts frames correctly, which is the only part of *Frame budget* a
/// Mac can settle.
///
/// `page-transitions` requires a transition to hold "the display's refresh rate, and a
/// dropped frame during a turn is treated as a defect". A simulator draws at this Mac's
/// refresh rate, so a rate measured here would be a fact about the Mac and about nothing
/// else. **No case below asserts a frame rate, and none may be added.** Each case hands
/// ``FrameRun`` a timetable it invented and checks the arithmetic that comes back.
///
/// The interval every case uses is 0.01 seconds. No display runs at that rate, so no case
/// can be misread as a claim about a device. The rate itself is read from the display at run
/// time by ``FrameProbe`` and is reported, never asserted.
///
/// Android's `FrameRunTest` asserts the same table, case for case.
@Suite("Frame run")
struct FrameRunTests {

    /// Deliberately no display's frame interval.
    private let interval = 0.01

    // MARK: - Counting

    @Test("It counts every frame it is handed")
    func countsFrames() {
        var run = FrameRun(isEnabled: true)
        run.begin()
        for step in 0..<10 {
            run.record(at: Double(step) * interval, expecting: interval)
        }
        #expect(run.delivered == 10)
        #expect(run.dropped == 0)
    }

    @Test("A frame that never arrived is one dropped frame")
    func countsOneDrop() {
        var run = FrameRun(isEnabled: true)
        run.begin()
        run.record(at: 0, expecting: interval)
        run.record(at: interval, expecting: interval)
        run.record(at: interval * 3, expecting: interval)
        #expect(run.delivered == 3)
        #expect(run.dropped == 1)
    }

    @Test("Two frames missing from one gap are two dropped frames")
    func countsTwoDrops() {
        var run = FrameRun(isEnabled: true)
        run.begin()
        run.record(at: 0, expecting: interval)
        run.record(at: interval * 3, expecting: interval)
        #expect(run.dropped == 2)
    }

    @Test("The span is the time from the first frame to the last")
    func spanIsMeasured() {
        var run = FrameRun(isEnabled: true)
        run.begin()
        run.record(at: 5, expecting: interval)
        run.record(at: 5 + interval, expecting: interval)
        run.record(at: 5.25, expecting: interval)
        #expect(abs(run.span - 0.25) < 0.000_001)
    }

    // MARK: - What it refuses to infer

    @Test("An interval the display did not report infers no drops")
    func noIntervalNoDrops() {
        var run = FrameRun(isEnabled: true)
        run.begin()
        run.record(at: 0, expecting: 0)
        run.record(at: 10, expecting: 0)
        #expect(run.delivered == 2)
        #expect(run.dropped == 0)
    }

    @Test("A frame stamped no later than the one before it drops nothing")
    func outOfOrderFrame() {
        var run = FrameRun(isEnabled: true)
        run.begin()
        run.record(at: interval, expecting: interval)
        run.record(at: interval, expecting: interval)
        run.record(at: 0, expecting: interval)
        #expect(run.delivered == 3)
        #expect(run.dropped == 0)
    }

    @Test("A gap wide enough to be nonsense is counted but bounded")
    func pathologicalGap() {
        var run = FrameRun(isEnabled: true)
        run.begin()
        run.record(at: 0, expecting: interval)
        run.record(at: 1_000_000, expecting: interval)
        #expect(run.dropped == 999)
    }

    // MARK: - Not running when no page is turning

    @Test("A run that has not begun counts nothing")
    func silentBeforeBegin() {
        var run = FrameRun(isEnabled: true)
        run.record(at: 0, expecting: interval)
        #expect(run.isRecording == false)
        #expect(run.delivered == 0)
    }

    @Test("A run that has ended counts nothing more")
    func silentAfterEnd() {
        var run = FrameRun(isEnabled: true)
        run.begin()
        run.record(at: 0, expecting: interval)
        run.end()
        run.record(at: interval, expecting: interval)
        #expect(run.isRecording == false)
        #expect(run.delivered == 1)
    }

    @Test("A disabled run never starts, so an unarmed build counts nothing")
    func disabledNeverStarts() {
        var run = FrameRun(isEnabled: false)
        run.begin()
        run.record(at: 0, expecting: interval)
        #expect(run.isRecording == false)
        #expect(run.delivered == 0)
    }

    @Test("Beginning again while a turn is still running keeps the count")
    func beginIsNotRestart() {
        var run = FrameRun(isEnabled: true)
        run.begin()
        run.record(at: 0, expecting: interval)
        run.begin()
        run.record(at: interval, expecting: interval)
        #expect(run.delivered == 2)
    }
}
