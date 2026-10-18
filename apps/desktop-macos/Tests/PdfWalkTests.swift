import AppKit
import StoryArcCore
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The PDF reader windows over the corpus PDFs, driven inside the app: the text PDF gets
    /// the text layer, its outline as chapter markers, a search that jumps, a selection with
    /// a mark drawn back; the scan gets none of it. Task 4.6's walk.
    @MainActor
    @Suite("PDF walk")
    struct PdfWalkTests {
        @Test("The text PDF searches, jumps, selects and marks; the scan offers no text controls")
        func textAndScan() async throws {
            let library = try await Walk.fixtureLibrary()
            let publication = try #require(Walk.publication(named: "text-pages", in: library))
            let target = try #require(library.target(for: publication))
            try Walk.open(target)
            let window = try #require(await Walk.until { Walk.readerWindows(for: target).first })
            let state = try #require(await Walk.until { ReaderStates.shared.state(for: target) })
            let text = try #require(await Walk.until(.seconds(15)) { state.pdfText }, "the text layer was not opened")
            _ = await Walk.until { state.model.pages.count == 3 ? true : nil }

            // The outline is the chapter markers, so the slider's ticks and the contents menu have them.
            #expect(await Walk.until { state.markers.count == 3 ? true : nil } == true)
            #expect(state.markers.map(\.title) == ["Chapter One", "Chapter Two", "Chapter Three"])
            ConformanceLog.note("PDF outline", "\(state.markers.count) markers from the outline", wave: 4)

            // A search from the chrome lists the hits; the hit's page is where the reader jumps.
            await text.search("three")
            let hit = try #require(text.hits.first)
            #expect(hit.page == 2)
            ConformanceLog.note("PDF search", "\(text.hits.count) hits for three, first on page \(hit.page)", wave: 4)
            state.jump(to: hit.page)
            #expect(await Walk.until { state.model.currentIndex == 2 ? true : nil } == true)
            #expect(state.returnIndex == 0)

            // A selection on the page in front, marked, is drawn back on that page alone.
            await text.select(onPage: 2, from: CGPoint(x: 0.02, y: 0.02), to: CGPoint(x: 0.98, y: 0.98))
            #expect(text.selection?.text.contains("Chapter Three") == true)
            let selected = text.selection?.text.count ?? 0
            ConformanceLog.note("PDF selection", "\(selected) characters selected on page 2", wave: 4)
            let mark = try #require(await text.highlight(.blue))
            await text.resolveMarks(onPage: 2)
            #expect(text.marks(onPage: 2).contains { $0.id == mark.id })
            await text.remove(mark.id)
            await Walk.close([window])

            let scan = try #require(Walk.publication(named: "image-pages", in: library))
            let scanTarget = try #require(library.target(for: scan))
            try Walk.open(scanTarget)
            let scanWindow = try #require(await Walk.until { Walk.readerWindows(for: scanTarget).first })
            let scanState = try #require(await Walk.until { ReaderStates.shared.state(for: scanTarget) })
            _ = await Walk.until { scanState.model.pages.count == 3 ? true : nil }
            await Walk.settle()
            #expect(scanState.pdfText == nil)
            ConformanceLog.note("PDF scan", "no text layer, \(scanState.markers.count) markers", wave: 4)
            #expect(scanState.markers.isEmpty)
            await Walk.close([scanWindow])
        }
    }
}
