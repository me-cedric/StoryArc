#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing

import StoryArcCore
@testable import ReaderFeature

/// `foldables-and-iphone-duo` 1.4: the three notices over the reader's page (`NetworkNotice`,
/// the voice-stopped banner and the return offer) never cross a vertical fold.
///
/// Each notice needs a state of its own to appear (a stalled page, a voice that was stopped, a
/// jump), so a notice as wide as the reader stands in for all three, drawn the way they are drawn:
/// in an overlay of the reader, through ``OffTheFold``. The source check below holds that all three
/// go through it.
///
/// **Proved able to fail**, per AGENTS.md §5: `OffTheFold` without its width failed both
/// off-centre cases by name. Reverted.
@MainActor
@Suite("The notices over the page keep off the fold", .serialized)
struct NoticesOffTheFoldTests {
    /// Where the stand-in notice landed, in the window.
    private final class Frame {
        var value: CGRect = .zero
    }

    /// The frame of a notice as wide as the reader, 669 points across, with `split` applied.
    private func notice(split: HingeSpreadSplit?) async throws -> CGRect {
        let frame = Frame()
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 669, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: Color.black.overlay(alignment: .bottom) {
                Color.blue
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame.value = $0 }
                    .modifier(OffTheFold(split: split))
            }
        )
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let deadline = Date().addingTimeInterval(5)
        while frame.value == .zero {
            try #require(Date() < deadline, "the notice was never laid out")
            try await Task.sleep(for: .milliseconds(20))
        }
        return frame.value
    }

    @Test("Off-centre folds: the notice takes the wider side and never crosses the fold", arguments: [
        (start: CGFloat(200), end: CGFloat(212)),
        (start: CGFloat(450), end: CGFloat(462)),
    ])
    func offCentreFold(start: CGFloat, end: CGFloat) async throws {
        let split = hingeSpreadSplit(containerWidth: 669, hingeStart: start, hingeEnd: end)

        let frame = try await notice(split: split)

        #expect(frame.maxX <= start || frame.minX >= end, "\(frame) crosses the fold at \(start)...\(end)")
        #expect(frame.width == max(start, 669 - end), "\(frame) is not the wider side")
    }

    @Test("With no fold the notice draws as before, across the whole reader")
    func noFold() async throws {
        let frame = try await notice(split: nil)

        #expect(frame.minX == 0)
        #expect(frame.width == 669)
    }

    @Test("All three notices go through OffTheFold")
    func allThree() throws {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/ReaderFeature/ReaderView.swift")
        let source = try String(contentsOf: file, encoding: .utf8)

        #expect(source.contains("voiceStoppedOverlay.modifier(OffTheFold(split: foldSplit))"))
        #expect(source.contains("returnOffer.modifier(OffTheFold(split: foldSplit))"))
        let network = try #require(source.range(of: "NetworkNotice("))
        let rest = source[network.upperBound...]
        let close = try #require(rest.range(of: "onLeave: { dismiss() }\n            )"))
        #expect(rest[close.upperBound...].hasPrefix("\n            .modifier(OffTheFold(split: foldSplit))"))
    }
}
#endif
