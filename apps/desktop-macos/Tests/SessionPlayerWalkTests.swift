import AppKit
import Foundation
import Playback
import StoryArcCore
import SwiftUI
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The voice's full player (`ebook-reader`, *The same controls as a narrated book*): the session player window
    /// over a book being read aloud carries the chapters, the sleep timer and the speed, as a narrated book's does.
    @MainActor
    @Suite("Session player walk")
    struct SessionPlayerWalkTests {
        @Test("A voice's full player offers the chapters, the sleep timer and the speed")
        func voiceControls() async throws {
            let library = try await Walk.library()
            let centre = PlayerCentre.shared
            let path = "/books/session-walk.epub"
            let publication = Publication(
                identity: .init(normalizedPath: path), format: .epub, displayTitle: "Spoken Walk", origin: .inferred
            )
            centre.begin(SpokenBook(publication: publication, url: URL(filePath: path)), source: FakeNarratedSource())
            defer { centre.end() }

            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SessionPlayerWindow(library: library)
            ))
            window.setContentSize(NSSize(width: 420, height: 640))
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            let names: [String] = await Walk.until(.seconds(10)) { () -> [String]? in
                let all = AccessibilityAudit.controls(in: window).map(\.name)
                return all.contains { $0.contains("Sleep") } ? all : nil
            } ?? []
            for wanted in ["Chapters", "Sleep", "Speed"] {
                #expect(names.contains { $0.contains(wanted) }, "no \(wanted) control in \(names)")
            }
            let offered = names.joined(separator: ", ")
            ConformanceLog.note("voice player", "the voice's full player offers \(offered)", wave: 4)
        }
    }
}
