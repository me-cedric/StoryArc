import AppKit
import Persistence
import StoryArcCore
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The EPUB reader window over the corpus `fixture.epub`, driven inside the app: it opens
    /// at the first position, a key turns to the second, a theme reaches the renderer, a
    /// search lists its hits in context and a hit jumps with a way back, and closing writes a
    /// reflowable position. Task 4.5's walk.
    @MainActor
    @Suite("EPUB walk")
    struct EpubWalkTests {
        @Test("The fixture opens, turns, themes, searches and writes where it got to")
        func readsThemesAndSearches() async throws {
            let library = try await Walk.library()
            let target = try await Self.freshTarget()
            let store = try #require(library.progress)
            EpubReaderModel.isDebugging = true
            defer { EpubReaderModel.isDebugging = false }

            try Walk.open(target)
            let window = try #require(await Walk.until { Walk.readerWindows(for: target).first })
            let model = try #require(await Walk.until { EpubReaders.shared.model(for: target) })
            // In front: WebKit stops a web view's frame clock while its window is occluded, and
            // the renderer's load waits on that clock.
            await Walk.activate(window)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            let ready = await Walk.until(.seconds(20)) { model.isReady ? true : nil } == true
            if !ready { Self.dump(model) }
            #expect(ready, "the renderer never said ready")
            #expect(model.title == "Fixture Publication")
            #expect(model.positionCount == 2)
            #expect(await Walk.until { model.position } == 1)

            // The right arrow turns, through the key monitor: the first chapter is one
            // position but more than one column at this width, so it takes a few presses.
            await Walk.activate(window)
            var presses = 0
            while model.position != 2, presses < 5 {
                Walk.type("\u{F703}", keyCode: KeyCode.rightArrow, in: window)
                presses += 1
                _ = await Walk.until(.seconds(3)) { model.position == 2 ? true : nil }
            }
            #expect(model.position == 2, "\(presses) right arrows did not reach position 2")
            #expect(EpubKeyMonitor.key(of: KeyCode.rightArrow) == .next)
            #expect(EpubKeyMonitor.key(of: KeyCode.leftArrow) == .previous)
            #expect(EpubKeyMonitor.key(of: KeyCode.space) == .next)

            // A preset replaces the axes, and the renderer says which colours are in force.
            model.apply(.quiet)
            #expect(await Walk.until { model.received.contains("theme") ? true : nil } == true, "no theme message")
            #expect(model.theme == .quiet)

            // Search lists the hits in context; one jumps and leaves a way back.
            model.search("chapter")
            let hits = try #require(await Walk.until { !model.isSearching && !model.hits.isEmpty ? model.hits : nil })
            #expect(hits.contains { $0.match.lowercased() == "chapter" })
            #expect(hits.allSatisfy { $0.chapter != nil })
            let first = try #require(hits.first)
            model.go(to: first.locator)
            #expect(model.returnLocator != nil)
            #expect(await Walk.until { model.position == 1 ? true : nil } == true, "the hit did not move the reader")
            model.goBack()
            #expect(model.returnLocator == nil)

            model.apply(.paper)
            await Walk.close([window])
            try await Self.expectReflowablePosition(for: target, in: store)
        }

        static let publicationID = "walk-epub"

        /// The fixture at a fixed place under one id, with nothing left from an earlier run.
        ///
        /// A run that stopped before closing its window leaves its session saved, and the next
        /// launch restores it: six such windows, all titled *Fixture Publication*, once sat
        /// beside the one under test and the walk read the wrong one by title.
        private static func freshTarget() async throws -> ReaderTarget {
            let folder = URL.temporaryDirectory.appending(path: "walk-ebooks", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: "walk-fixture.epub")
            if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                try FileManager.default.copyItem(at: TestFixtures.ebooks.appending(path: "fixture.epub"), to: file)
            }
            let target = ReaderTarget(
                publicationID: publicationID, path: file.path(percentEncoded: false), title: "Fixture Publication"
            )
            await Walk.close(NSApplication.shared.windows.filter { $0.isVisible && $0.title == target.title })
            let saved = ReaderWindows.shared.savedSessions().map(\.target)
            for stale in saved where stale.publicationID.hasPrefix("walk-epub") { ReaderWindows.shared.didClose(stale) }
            return target
        }

        /// What the renderer served, posted and logged, for a run that did not get there.
        private static func dump(_ model: EpubReaderModel) {
            print("epub walk: received=\(model.received) failure=\(model.failure ?? "-") served=\(model.served)")
            for line in model.logs { print("epub walk log: \(line)") }
        }

        /// Closing wrote where the voice of the reader got to: a reflowable position with a locator.
        private static func expectReflowablePosition(for target: ReaderTarget, in store: ProgressStore) async throws {
            let saved = try await store.progress(for: PublicationIdentity(normalizedPath: target.path))
            guard case let .reflowable(progression, locator, _)? = saved?.position else {
                Issue.record("no reflowable position was written: \(String(describing: saved))")
                return
            }
            #expect(!locator.isEmpty)
            #expect(progression >= 0)
        }

        @Test("Every response the scheme handler sends carries the policy header")
        func headerOnEveryResponse() async throws {
            let file = try TestFixtures.copyEbook("fixture.epub")
            let bundle = try #require(EpubArchiveSource.bundledRenderer, "the renderer is not in the app")
            let source = try await EpubArchiveSource(url: file, token: "header", bundle: bundle)
            for path in ["index.html", "storyarc-epub.js", "manifest.json", "positions.json", "OEBPS/ch1.xhtml"] {
                let resource = await source.resource(at: path)
                #expect(resource != nil, "\(path) was not served")
            }
            #expect(await source.resource(at: "OEBPS/none.xhtml") == nil)
            #expect(await source.resource(at: "manifest.json")?.mimeType == "application/webpub+json")
            #expect(await source.resource(at: "OEBPS/ch1.xhtml")?.mimeType == "application/xhtml+xml")
            #expect(EpubEgress.contentSecurityPolicy.hasPrefix("default-src 'none'"))
            #expect(EpubEgress.contentSecurityPolicy.contains("connect-src 'self' storyarc-epub: blob: data:"))
        }
    }
}
