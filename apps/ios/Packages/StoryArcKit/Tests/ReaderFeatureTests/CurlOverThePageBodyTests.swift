import CoreGraphics
import Foundation
import SwiftUI
import Testing

import StoryArcCore

@testable import ReaderFeature

/// That the curl stands over the reader's normal page body, and lifts the last page off the
/// end screen.
///
/// D33 (task 8.16): at rest Curl draws the normal page body, with its fit, its pinch and its
/// PDF marks, and the shader runs only while a turn does. Two things follow and both are
/// asserted here. The finger belongs to the page's own pan, so a zoomed page pans and does
/// not turn. And the shader starts and ends where the body draws the page, so the fit
/// survives a turn rather than jumping to fit-to-screen and back.
///
/// D10 (task 8.5): the end screen is the sheet beneath the last page. The shader leaves it
/// transparent past the fold, and the matte stops at the same curve.
///
/// Android's `CurlOverThePageBodyTest` asserts the same table.
@Suite("Curl over the page body")
struct CurlOverThePageBodyTests {

    // MARK: - Who owns the finger

    @Test("A zoomed page pans and does not turn")
    func zoomedPagePans() {
        // A page zoomed past the screen's width has sideways slack, and the finger is the
        // page's to pan however sideways it moves.
        #expect(!pagePanTurns(pageWidth: 900, boundsWidth: 400, velocity: CGPoint(x: -800, y: 0)))
    }

    @Test("A page with no sideways slack turns on a sideways finger and scrolls on a downward one")
    func fittedPageTurns() {
        #expect(pagePanTurns(pageWidth: 400, boundsWidth: 400, velocity: CGPoint(x: -800, y: 30)))
        // Fit-to-width: as wide as the screen, taller than it. Down is a scroll.
        #expect(!pagePanTurns(pageWidth: 400, boundsWidth: 400, velocity: CGPoint(x: 30, y: -800)))
        // A hairline of rounding is not slack.
        #expect(pagePanTurns(pageWidth: 400.5, boundsWidth: 400, velocity: CGPoint(x: 800, y: 0)))
    }

    @Test("The slack is the page's, not the scroll content's")
    func slackIsThePages() {
        // A page taller than the phone's shape, at fit-to-width: the scroll content is the
        // screen times the zoom, wider than the screen, but the page inside it is exactly as
        // wide as the screen. That page turns.
        let tall = CGSize(width: 1000, height: 3000)
        let zoom = OwedFit(pageID: "p", mode: .width, imageSize: tall, viewport: phone)
            .scale(upTo: OwedFit.zoomCeiling)
        #expect(phone.width * zoom > phone.width + 1)
        #expect(
            pagePanTurns(
                pageWidth: pageWidth(image: tall, bounds: phone, zoomScale: zoom),
                boundsWidth: phone.width,
                velocity: CGPoint(x: -800, y: 0)
            )
        )
    }

    @Test("A flick is 800 points a second in turn-space, the number Android uses in dp")
    func flickThreshold() {
        let slow = CurlTurn.predictedTravel(velocity: 780)
        let fast = CurlTurn.predictedTravel(velocity: 820)
        #expect(!CurlTurn.flicks(velocity: slow, progress: 0.2))
        #expect(CurlTurn.flicks(velocity: fast, progress: 0.2))
    }

    // MARK: - The fit survives a turn

    private let phone = CGSize(width: 400, height: 800)
    /// Wider than the phone's shape, so fit-to-screen leaves it narrower than the screen.
    private let page = CGSize(width: 1000, height: 1200)

    /// Where the page itself lands inside a frame, fitted as the image view fits it.
    private func pageRect(in frame: CGRect, image: CGSize) -> CGRect {
        let scale = min(frame.width / image.width, frame.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
            width: size.width, height: size.height
        )
    }

    @Test("Fit to screen opens on the whole screen")
    func screenOpensWhole() {
        let frame = CurlSheetFrame.opening(
            imageSize: page, viewport: phone, fit: .screen, carried: nil, isRightToLeft: false
        )
        #expect(frame == CGRect(origin: .zero, size: phone))
    }

    @Test("Fit to width opens with the page as wide as the screen, at its top")
    func widthOpensAtTheTop() {
        let tall = CGSize(width: 1000, height: 3000)
        let frame = CurlSheetFrame.opening(
            imageSize: tall, viewport: phone, fit: .width, carried: nil, isRightToLeft: false
        )
        let drawn = pageRect(in: frame, image: tall)
        #expect(abs(drawn.width - phone.width) < 0.5)
        #expect(abs(drawn.minY) < 0.5)
        // The page itself starts at the screen's left edge, not the box it is fitted in: a tall
        // page sits in the middle of that box, so the box's edge is blank margin (23.2).
        #expect(abs(drawn.minX) < 0.5)
    }

    @Test("A carried zoom in a right-to-left publication opens against the right")
    func carriedZoomOpensRight() {
        let tall = CGSize(width: 1000, height: 3000)
        let frame = CurlSheetFrame.opening(
            imageSize: tall, viewport: phone, fit: .width, carried: 2, isRightToLeft: true
        )
        let drawn = pageRect(in: frame, image: tall)
        #expect(abs(drawn.maxX - phone.width) < 0.5)
        #expect(drawn.width > phone.width * 1.9)
    }

    @Test("The frame a page opens at is the frame the scroll view applies")
    func openingMatchesTheScrollView() {
        // `OwedFit` is what `ScrollingPage` sets its zoom from, and the image view is the
        // bounds times that zoom.
        let owed = OwedFit(pageID: "p", mode: .height, imageSize: page, viewport: phone)
        let frame = CurlSheetFrame.opening(
            imageSize: page, viewport: phone, fit: .height, carried: nil, isRightToLeft: false
        )
        #expect(abs(frame.width - phone.width * owed.scale(upTo: OwedFit.zoomCeiling)) < 0.001)
    }

    // MARK: - The end screen beneath

    @Test("The sheet's outline is the whole page at rest")
    func outlineAtRest() {
        let outline = CurlTurn.sheetOutline(width: 400, height: 800, progress: 0, isRightToLeft: false)
        #expect(outline.dropFirst().dropLast().allSatisfy { $0.x == 400 })
    }

    @Test("Past the rim the end screen shows, and before it the sheet covers it")
    func outlineStopsAtTheRim() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 800)
        let path = CurlSheetShape(progress: 0.5, isRightToLeft: false).path(in: rect)
        #expect(path.contains(CGPoint(x: 20, y: 400)))
        #expect(!path.contains(CGPoint(x: 380, y: 400)))
        // The rim is a curve, not a line: the shader's own `PageRoll` bows it.
        let outline = CurlTurn.sheetOutline(width: 400, height: 800, progress: 0.5, isRightToLeft: false)
        let rims = Set(outline.dropFirst().dropLast().map { Int($0.x.rounded()) })
        #expect(rims.count > 2)
    }

    @Test("Right to left the sheet lifts from the other edge")
    func outlineMirrors() {
        let rect = CGRect(x: 0, y: 0, width: 400, height: 800)
        let path = CurlSheetShape(progress: 0.5, isRightToLeft: true).path(in: rect)
        #expect(path.contains(CGPoint(x: 380, y: 400)))
        #expect(!path.contains(CGPoint(x: 20, y: 400)))
    }

    @Test("A tap past the last page curls to the end screen, and only forward")
    func tapCurlsToTheEnd() {
        #expect(CurlRequest.endsAhead(isForward: true, page: 9, pageCount: 10))
        #expect(!CurlRequest.endsAhead(isForward: false, page: 9, pageCount: 10))
        #expect(!CurlRequest.endsAhead(isForward: true, page: 8, pageCount: 10))
        #expect(!CurlRequest.endsAhead(isForward: true, page: 0, pageCount: 0))
    }

    @Test("After a curl the end screen is up at once, and every other way fades it in")
    func endScreenArrivesAtOnce() throws {
        // A fade from nothing after the curl drew the last page flat again under the end
        // screen for its first frames.
        #expect(EndOfPublication.arrival(afterCurl: true) == nil)
        #expect(EndOfPublication.arrival(afterCurl: false) != nil)
        let turning = try source("ReaderTurning.swift")
        #expect(turning.contains("withAnimation(EndOfPublication.arrival(afterCurl: curled))"))
    }

    @Test("The clear sheet is transparent, so the end screen shows through it")
    func clearSheetIsClear() throws {
        let image = try #require(CurlSheetFrame.clear)
        let data = try #require(image.dataProvider?.data as Data?)
        #expect(data.allSatisfy { $0 == 0 })
    }

    // MARK: - The wiring

    private static let sources: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/ReaderFeature")

    private func source(_ name: String) throws -> String {
        try #require(
            try? String(contentsOf: Self.sources.appending(path: name), encoding: .utf8),
            "\(name) could not be read — has it moved?"
        )
    }

    @Test("The curl stands over the page body and hands it the drag")
    func curlStandsOverTheBody() throws {
        let containers = try source("ReaderContainers.swift")
        #expect(containers.contains("content: page(at: displayIndex),"), "Curl no longer draws the page body at rest.")
        #expect(containers.contains("endsHere: next == nil,"), "The last page no longer knows the end screen is next.")
        #expect(
            containers.contains("underneath: endOfPublication,"),
            "The end screen is no longer under the last page."
        )

        let curl = try source("CurledPages.swift")
        #expect(
            curl.contains(".environment(\\.curlDrag, wired(in: size, at: screen))"),
            "The body is no longer handed the curl's drag."
        )
        #expect(
            curl.contains(".allowsHitTesting(false)"),
            "The turning sheet takes touches again, so a drag cannot take over a settle."
        )
        #expect(curl.contains("if isTurning {"), "The shader is drawn at rest again, over the page body.")
        #expect(curl.contains("underneath.accessibilityHidden(true)"))
    }

    @Test("The page's own pan owns the curl's drag, and the scroll view waits for it")
    func panOwnsTheDrag() throws {
        let swipe = try source("ZoomablePageSwipe.swift")
        #expect(swipe.contains("if onCurl != nil { scrollView.panGestureRecognizer.require(toFail: pan) }"))
        #expect(swipe.contains("case .began: onCurl.handle(.began(travel: travel))"))
        #expect(swipe.contains("onCurl == nil && (recogniser === swipe || other === swipe)"))
    }
}
