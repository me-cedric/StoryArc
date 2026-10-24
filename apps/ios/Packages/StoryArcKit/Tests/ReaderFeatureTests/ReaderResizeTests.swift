#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing

import Playback
import StoryArcCore
@testable import ReaderFeature

/// `foldables-and-iphone-duo` D5 and 2.6: opening or closing a foldable is a resize, and a resize
/// keeps the page, the open menu and the voice.
///
/// A real `ReaderView` in a real window, resized from the outer display of an iPhone Duo to the
/// inner one and back, and in Split View from the inner display to half of it with an inset on
/// the left. The page lives in the model and the menu in the view's own state, so a reader that
/// rebuilt its state on a resize would open the publication again, which ends the voice, and
/// would present the menu again.
///
/// **Proved able to fail**, per AGENTS.md §5: an `.id` keyed on the pages' size around the whole
/// of `ReaderView.body` failed by name: `openCount` went past 1, the menu was presented again,
/// and the voice ended. Reverted. The same `.id` on the inner `ZStack` passes, and rightly: the
/// state a reader keeps lives above it.
@MainActor
@Suite("A resize keeps the reader", .serialized)
struct ReaderResizeTests {
    nonisolated private static let outer = CGSize(width: 466, height: 678)
    nonisolated private static let inner = CGSize(width: 669, height: 951)
    nonisolated private static let halfInner = CGSize(width: 334, height: 951)

    private static let comic: URL = {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while dir.path != "/" {
            let candidate = dir.appending(path: "packages/test-fixtures")
            if FileManager.default.fileExists(atPath: candidate.appending(path: "manifest.json").path) {
                return candidate.appending(path: "comics/natural-sort.cbz")
            }
            dir = dir.deletingLastPathComponent()
        }
        fatalError("fixture corpus not found above \(#filePath)")
    }()

    @Test(
        "Opening and closing the device, and Split View, keep the page, the menu and the voice",
        arguments: [
            (sizes: [outer, inner, outer], leftInset: CGFloat(0)),
            (sizes: [inner, halfInner, inner], leftInset: CGFloat(24)),
        ]
    )
    func aResizeKeepsTheReader(sizes: [CGSize], leftInset: CGFloat) async throws {
        let centre = PlayerCentre()
        let model = ReaderModel(
            publication: Publication(
                identity: PublicationIdentity(normalizedPath: Self.comic.path),
                format: .cbz,
                displayTitle: "natural-sort.cbz",
                origin: .inferred
            ),
            url: Self.comic,
            centre: centre
        )
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: sizes[0]),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: ReaderView(model: model, isShowingMenu: true).safeAreaPadding(.leading, leftInset)
        )
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        try await until { model.openCount == 1 }
        await model.go(to: 2)
        centre.begin(
            SpokenBook(publication: Self.spoken, url: URL(fileURLWithPath: "/spoken/book")),
            source: SilentVoice()
        )
        try await until { window.attachedSheet != nil }
        let menu = window.attachedSheet

        for size in sizes.dropFirst() {
            window.setContentSize(size)
            try await Task.sleep(for: .milliseconds(400))
        }

        #expect(model.openCount == 1, "the reader opened the publication again, so it rebuilt its state")
        #expect(model.currentIndex == 2, "the reader is on page \(model.currentIndex + 1)")
        #expect(window.attachedSheet === menu, "the menu was closed or presented again")
        #expect(centre.book != nil, "the resize ended the voice")
    }

    private static let spoken = Publication(
        identity: PublicationIdentity(normalizedPath: "/spoken/book"),
        format: .epub,
        displayTitle: "The Long Field",
        origin: .inferred
    )

    /// Waits for `condition`, for ten seconds at most.
    private func until(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition() {
            try #require(Date() < deadline, "timed out")
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

/// A voice with nowhere for its words to go. This suite only needs it to exist.
private final class SilentVoice: PlaybackSource {
    var moved: (@MainActor () -> Void)?
    var ended: (@MainActor () -> Void)?
    let parts: [PlaybackPart] = [PlaybackPart(index: 0, title: nil, duration: nil)]
    let place = PlaybackPlace(partIndex: 0, offset: 0)
    let skipUnit: SkipUnit = .sentence
    let unreadablePartCount = 0

    func play() {}
    func pause() {}
    func stop() {}
    func setSpeed(_ speed: PlaybackSpeed) {}
    func seek(toPart index: Int, offset: TimeInterval) {}
    func skip(_ direction: SkipDirection, by interval: TimeInterval) {}
}
#endif
