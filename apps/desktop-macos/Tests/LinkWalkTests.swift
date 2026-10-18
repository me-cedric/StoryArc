import AppKit
import Testing

@testable import StoryArc

extension WindowWalks {
    /// The `storyarc://` link handed to the running app the way Launch Services hands it: through
    /// `application(_:open:)`. A title opens its reader window, a source opens Preferences on the
    /// Sources tab, an unknown title is said in grey, and a command changes nothing. Task 5.8.
    @MainActor
    @Suite("Link walk")
    struct LinkWalkTests {
        @Test("A link opens a title or a source, names what is not there, and runs no command")
        func followsLinks() async throws {
            let library = try await Walk.fixtureLibrary()
            let publication = try #require(Walk.publication(named: "natural-sort", in: library))
            let target = try #require(library.target(for: publication))
            let title = Self.encoded(publication.displayTitle)
            await Walk.close(Walk.readerWindows(for: target))
            library.dismissLinksNotFound()

            try Self.send("storyarc://publication/\(title)")
            let window = await Walk.until { Walk.readerWindows(for: target).first }
            #expect(window != nil, "the link did not open \(publication.displayTitle)")
            await Walk.close(window.map { [$0] } ?? [])

            let windows = NSApplication.shared.windows.filter(\.isVisible).count
            let tab = MacSettings.shared.settingsTab
            for command in ["storyarc://settings/reset", "storyarc://publication/\(title)/delete", "storyarc:"] {
                try Self.send(command)
            }
            await Walk.settle()
            #expect(NSApplication.shared.windows.filter(\.isVisible).count == windows, "a command opened a window")
            #expect(MacSettings.shared.settingsTab == tab && library.linksNotFound.isEmpty)

            try Self.send("storyarc://publication/Nowhere%20Book")
            #expect(await Walk.until { library.linksNotFound == ["Nowhere Book"] ? true : nil } == true)
            library.dismissLinksNotFound()

            let source = try #require(library.model.registry.sources.first { $0.kind == .localFolder })
            MacSettings.shared.settingsTab = .about
            try Self.send("storyarc://source/\(Self.encoded(source.displayName))")
            #expect(await Walk.until { MacSettings.shared.settingsTab == .sources ? true : nil } == true)
            let seen = "opened \(publication.displayTitle), named Nowhere Book, showed \(source.displayName)"
            ConformanceLog.note("link", seen, wave: 5)
            await Walk.close(NSApplication.shared.windows.filter {
                $0.isVisible && $0.identifier?.rawValue.contains("Settings") == true
            })
        }

        private static func encoded(_ name: String) -> String {
            name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name
        }

        /// What Launch Services does with a link the app registered: SwiftUI's delegate passes
        /// `application(_:open:)` on to `MacAppDelegate`.
        private static func send(_ link: String) throws {
            let delegate = try #require(NSApplication.shared.delegate)
            #expect(delegate.responds(to: #selector(NSApplicationDelegate.application(_:open:))))
            delegate.application?(NSApplication.shared, open: [try #require(URL(string: link))])
        }
    }
}
