import AppKit
import Persistence
import StoryArcCore
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The reader's modes, driven inside the app over the fixture library: the transition and
    /// the continuous scroll, the fits, the adjustments, the end of a publication, and a jump
    /// with its way back. Each walk puts back what it changed for the series it read.
    @MainActor
    @Suite("Reader modes walk")
    struct ReaderModesWalkTests {
        /// Opens a fixture in a reader window, keyed, and waits for its pages.
        private func open(_ name: String) async throws -> (ReaderState, NSWindow) {
            let library = try await Walk.fixtureLibrary()
            let publication = try #require(Walk.publication(named: name, in: library))
            let target = try #require(library.target(for: publication))
            try Walk.open(target)
            let window = try #require(await Walk.until { Walk.readerWindows(for: target).first })
            let state = try #require(await Walk.until { ReaderStates.shared.state(for: target) })
            _ = await Walk.until { state.model.pages.isEmpty ? nil : true }
            await Walk.activate(window)
            return (state, window)
        }

        @Test("A chosen mode applies at once without losing the page, a key turns in it, and it comes back")
        func transitionModes() async throws {
            var (state, window) = try await open("natural-sort")
            defer { state.choose(.slide) }
            // One page a slot: a window wide enough for spreads (the runner's) would turn
            // two pages at a time, and the page numbers below count single pages.
            state.spreadMode = .single
            state.go(to: 3)
            _ = await Walk.until { state.model.currentIndex == 3 ? true : nil }

            state.choose(.fastFade)
            #expect(state.choices.effective == .fastFade)
            state.turn(by: 1)
            #expect(state.change == .fade)

            state.choose(.verticalScroll)
            #expect(state.isScrolling)
            #expect(state.shownIndex == 4, "choosing the scroll moved the reader to \(state.shownIndex)")
            Walk.press(" ", keyCode: KeyCode.space, in: window)
            let turned = await Walk.until { state.model.currentIndex == 5 ? true : nil }
            #expect(turned == true, "Space in the scroll left page \(state.model.currentIndex)")

            await Walk.close([window])
            (state, window) = try await open("natural-sort")
            #expect(state.model.settings.transition == .verticalScroll, "the mode was not remembered")
            state.choose(.slide)
            await Walk.close([window])
        }

        @Test("Fit width fills the width from the top, and a turn keeps it")
        func fitWidth() async throws {
            let (state, window) = try await open("natural-sort")
            defer { state.applyFit(.screen) }
            window.styleMask.remove(.resizable)
            defer { window.styleMask.insert(.resizable) }
            window.setFrame(NSRect(x: 100, y: 100, width: 1300, height: 700), display: true)
            state.spreadMode = .single
            _ = await Walk.until { state.model.displayImage(at: state.model.currentIndex) == nil ? nil : true }

            state.applyFit(.width)
            let fitted = await Walk.until { state.zoom.isZoomed ? state.zoom : nil }
            #expect(fitted != nil, "fit width left the page at fit-to-screen")
            #expect((fitted?.offset.height ?? 0) > 0, "fit width did not open at the top")

            state.turn(by: 1)
            _ = await Walk.until { state.model.currentIndex > 0 ? true : nil }
            try await Task.sleep(for: .milliseconds(300))
            #expect(state.zoom.isZoomed, "the turn dropped fit width")
            #expect(state.model.settings.fit == .width)
            await Walk.close([window])
        }

        @Test("Adjustments are kept for the series, and a page can be excused from the trim")
        func adjustments() async throws {
            var (state, window) = try await open("stored-entries")
            state.setAdjustments(ImageAdjustments(brightness: 0.3, isGreyscale: true, cropsBorders: true))
            state.setCropsPage(1, false)
            #expect(!state.adjustments(at: 1).cropsBorders)
            #expect(state.adjustments(at: 0).cropsBorders)
            state.choose(.fastFade)
            await Walk.close([window])

            (state, window) = try await open("stored-entries")
            #expect(state.adjustments.brightness == 0.3, "the adjustment was lost: \(state.adjustments)")
            #expect(state.adjustments.isGreyscale)
            state.setAdjustments(ImageAdjustments())
            state.choose(.slide)
            await Walk.close([window])
        }

        @Test("A turn past the last page shows the end, marks the publication finished and moves nothing")
        func reachingTheEnd() async throws {
            let (state, window) = try await open("stored-entries")
            let store = try #require(try await Walk.fixtureLibrary().progress)
            state.spreadMode = .single
            state.go(to: state.model.pages.count - 1)
            _ = await Walk.until { state.model.currentIndex == state.model.pages.count - 1 ? true : nil }

            Walk.press("\u{F703}", keyCode: KeyCode.rightArrow, in: window)
            #expect(await Walk.until { state.isAtEnd ? true : nil } == true)
            #expect(state.model.currentIndex == state.model.pages.count - 1)
            Walk.press("\u{F702}", keyCode: KeyCode.leftArrow, in: window)
            #expect(!state.isAtEnd)
            #expect(state.model.currentIndex == state.model.pages.count - 1, "the turn back moved the page")

            await Walk.close([window])
            let record = try await store.progress(for: state.model.publication.identity)
            #expect(record?.isFinished == true)
            try await store.forget(state.model.publication.identity)
        }

        @Test("A jump from the slider or the browser keeps the way back, and the browser leaves the reader alone")
        func jumpAndBack() async throws {
            let (state, window) = try await open("natural-sort")
            state.spreadMode = .single
            state.go(to: 1)
            _ = await Walk.until { state.model.currentIndex == 1 ? true : nil }
            state.isBrowsingPages = true
            try await Task.sleep(for: .milliseconds(300))
            #expect(state.model.currentIndex == 1, "opening the browser moved the reader")

            state.jump(to: 8)
            #expect(state.returnIndex == 1)
            _ = await Walk.until { state.model.currentIndex == 8 ? true : nil }
            state.goBack()
            #expect(await Walk.until { state.model.currentIndex == 1 ? true : nil } == true)
            #expect(state.returnIndex == nil)
            await Walk.close([window])
        }
    }
}
