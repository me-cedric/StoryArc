import Foundation
import QuartzCore
import Testing
import UIKit

import ReadiumNavigator
import StoryArcCore
@testable import EpubReaderFeature

/// The prose curl on a real book, in a window: the timing O14 asked for, and the finger.
///
/// `reader-theming-and-page-transitions` 4.3b, owner answer O14: measure first. Readium's
/// `PaginationView.slideToView` sleeps 100 ms when `animated` is false, and that path is the
/// one a turn across a chapter end takes. The fold cannot move until the page beneath has
/// been rastered, so the time from the first move to that raster is the stall.
///
/// Measured on 2026-10-07, iPhone 17 Pro simulator, 60 Hz, `fixture.epub`: inside a chapter
/// the move took 2 to 34 ms, under one frame in most turns; across the chapter end it took 108
/// to 112 ms, seven frames. So a turn across a chapter end rasters ahead (``ProsePages``), and
/// ``theBoundaryIsRasteredAhead()`` holds that to the book.
///
/// The numbers are printed, not asserted: a simulator draws at its Mac's rate, so a frame count
/// here is a statement about this Mac. What is asserted is which turns raster ahead.
///
/// **No pixel is compared here.** In this test host `drawHierarchy` gives a black image, so a
/// raster comparison would pass for the wrong reason. The frames lane compares the pixels.
@MainActor
@Suite("Prose curl on a book", .serialized)
struct ProseCurlOnABookTests {

    private static let corpus: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: candidate.appending(path: "manifest.json").path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    /// A reader with its navigator on screen, and the window that holds it.
    private struct Book {
        let reader: EpubReaderModel
        let navigator: EPUBNavigatorViewController
        let window: UIWindow
    }

    /// A reader with `fixture.epub` open in a window of an iPhone's size, in Curl.
    private func openBook() async throws -> Book {
        let url = Self.corpus.appending(path: "ebooks/fixture.epub")
        let reader = EpubReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: url.path),
                format: .epub,
                displayTitle: "fixture",
                origin: .embedded
            ),
            url: url
        )
        reader.transition = .pageCurl
        await reader.open()
        let navigator = try #require(reader.navigator)
        // The navigator inside a host, as `NavigatorHost` puts it: the sheet goes up in the
        // navigator view's superview.
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        host.addChild(navigator)
        navigator.view.frame = host.view.bounds
        host.view.addSubview(navigator.view)
        navigator.didMove(toParent: host)
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(3))
        // A loaded suite run can take longer than 3 s to report the first location, and a walk
        // that starts with none counts a crossing that is not there. On the runner of 2026-10-09
        // it took longer than 13 s, so the wait is up to 30 s and ends when the location comes.
        for _ in 0..<300 where navigator.currentLocation == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        return Book(reader: reader, navigator: navigator, window: window)
    }

    /// Where the reader is, once the sheet is off and Readium has reported where it left them.
    ///
    /// Polled, because the spring's completion runs when SwiftUI counts it logically complete,
    /// which was 400 to 450 ms in this test host, and a turn that springs back then moves the
    /// navigator back under the sheet.
    private func place(
        of navigator: EPUBNavigatorViewController,
        reader: EpubReaderModel? = nil
    ) async throws -> String {
        for _ in 0..<40 where reader?.proseCurl.isTurning == true {
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .milliseconds(700))
        let locator = navigator.currentLocation
        return "\(locator?.href.string ?? "?")@\(locator?.locations.progression ?? -1)"
    }

    /// Waits, for at most five seconds, until Readium has laid out the resource after the one
    /// on screen. The last resource has none after it.
    ///
    /// Readium preloads that resource after a turn, and on a loaded machine the preload took
    /// longer than the half second each step waits (2026-10-10). Until it is there,
    /// ``ProsePages/ahead(in:forward:isRightToLeft:over:)`` has nothing to raster, so a turn
    /// across the chapter end read as a crossing with nothing rastered ahead.
    private func nextResourceLaidOut(in page: UIView, after href: String, last: String?) async throws {
        guard let last, !href.hasSuffix(last) else { return }
        for _ in 0..<50 {
            if let paging = PaginatedScroll.find(in: page),
               ProsePages.spread(in: paging, at: paging.contentOffset.x + paging.bounds.width) != nil {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    @Test("A turn across a chapter end is rastered ahead, and a turn inside one is not")
    func theBoundaryIsRasteredAhead() async throws {
        let book = try await openBook()
        let navigator = book.navigator
        defer { book.window.isHidden = true }
        let clock = FrameClock()
        var crossings = 0

        for step in 0..<8 {
            let before = navigator.currentLocation?.href.string ?? "?"
            let page = try #require(navigator.view)
            try await nextResourceLaidOut(in: page, after: before, last: book.reader.readingOrder.last)
            let started = CACurrentMediaTime()
            clock.start()
            let leaving = try #require(page.raster(afterScreenUpdates: false))
            let ahead = ProsePages.ahead(in: page, forward: true, isRightToLeft: false, over: leaving)
            let moved = await navigator.goForward(options: NavigatorGoOptions(animated: false))
            let movedAt = CACurrentMediaTime()
            _ = page.raster(afterScreenUpdates: true)
            let ready = CACurrentMediaTime()
            let frames = clock.stop()
            try await Task.sleep(for: .milliseconds(500))
            let after = navigator.currentLocation?.href.string ?? "?"
            print(
                "ProseCurlTiming step=\(step) moved=\(moved) from=\(before) to=\(after)"
                    + " ahead=\(ahead != nil) move_ms=\(Int((movedAt - started) * 1000))"
                    + " ready_ms=\(Int((ready - started) * 1000)) frames=\(frames)"
                    + " interval_ms=\(Int(clock.interval * 1000))"
            )
            #expect((ahead != nil) == (after != before), "step \(step): \(before) to \(after)")
            if after != before { crossings += 1 }
        }
        // `fixture.epub` has two chapters, so the walk crosses one chapter end.
        #expect(crossings == 1)
    }

    @Test("A drag released past halfway turns the page, and one released short puts it back")
    func theReleaseDecides() async throws {
        let book = try await openBook()
        let reader = book.reader, navigator = book.navigator
        defer { book.window.isHidden = true }
        let start = try await place(of: navigator)

        reader.curlDrag(.began(travel: -10))
        #expect(reader.proseCurl.isTurning)
        reader.curlDrag(.changed(travel: -130))
        reader.curlDrag(.ended(travel: -130, velocity: 0))
        let shortOne = try await place(of: navigator, reader: reader)
        #expect(shortOne == start)
        #expect(!reader.proseCurl.isTurning)

        reader.curlDrag(.began(travel: -10))
        reader.curlDrag(.changed(travel: -300))
        reader.curlDrag(.ended(travel: -300, velocity: 0))
        let longOne = try await place(of: navigator, reader: reader)
        #expect(longOne != start)
        #expect(!reader.proseCurl.isTurning)
    }

    @Test("A drag that catches a settle takes it over, and can take the turn back")
    func aDragTakesOverASettle() async throws {
        let book = try await openBook()
        let reader = book.reader, navigator = book.navigator
        defer { book.window.isHidden = true }
        let start = try await place(of: navigator)

        reader.curlDrag(.began(travel: -10))
        reader.curlDrag(.changed(travel: -300))
        reader.curlDrag(.ended(travel: -300, velocity: 0))
        // Mid-spring, before the turn lands: the finger takes the page and carries it back.
        try await Task.sleep(for: .milliseconds(60))
        reader.curlDrag(.began(travel: 10))
        reader.curlDrag(.changed(travel: 600))
        // The finger holds the page past the time the caught spring would have landed in.
        try await Task.sleep(for: .milliseconds(600))
        #expect(reader.proseCurl.isTurning)
        reader.curlDrag(.ended(travel: 600, velocity: 0))

        let end = try await place(of: navigator, reader: reader)
        #expect(end == start)
        #expect(!reader.proseCurl.isTurning)
    }

    @Test("A tap rolls the page over with the same spring, one page on")
    func aTapTurnsOnePage() async throws {
        let book = try await openBook()
        let reader = book.reader, navigator = book.navigator
        defer { book.window.isHidden = true }
        let start = try await place(of: navigator)

        await reader.turn(forward: true)

        let end = try await place(of: navigator, reader: reader)
        #expect(end != start)
        #expect(!reader.proseCurl.isTurning)
    }

    @Test("At the first page a drag back lifts nothing")
    func theFirstPageLiftsNothing() async throws {
        let book = try await openBook()
        let reader = book.reader, navigator = book.navigator
        defer { book.window.isHidden = true }
        let start = try await place(of: navigator)

        reader.curlDrag(.began(travel: 10))
        reader.curlDrag(.changed(travel: 300))
        reader.curlDrag(.ended(travel: 300, velocity: 0))

        let end = try await place(of: navigator, reader: reader)
        #expect(end == start)
        #expect(!reader.proseCurl.isTurning)
    }
}

/// Counts display frames between `start` and `stop`.
@MainActor
final class FrameClock: NSObject {
    private var link: CADisplayLink?
    private(set) var count = 0
    private(set) var interval: Double = 0

    func start() {
        count = 0
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() -> Int {
        link?.invalidate()
        link = nil
        return count
    }

    @objc private func tick(_ link: CADisplayLink) {
        count += 1
        interval = link.targetTimestamp - link.timestamp
    }
}
