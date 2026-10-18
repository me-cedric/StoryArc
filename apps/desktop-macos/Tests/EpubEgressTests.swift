import AppKit
import Foundation
import Testing
import WebKit

@testable import StoryArc

/// A page served by the egress test: the shared eight-vector page, aimed at the collector.
private struct EgressPageSource: EpubResourceSource {
    let page: Data

    func resource(at path: String) async -> EpubResource? {
        guard path.hasPrefix("egress.html") else { return nil }
        return EpubResource(data: page, mimeType: "text/html")
    }
}

/// What one opening of the page measured.
private struct EgressRun {
    let served: [String]
    let arrived: [String]
    /// How many vectors the collector counts, from its own answer.
    let attempts: Int
}

extension WindowWalks {
    /// `desktop-experience`, *A book stays off the network on every desktop*, *Proof on each
    /// desktop*: the eight-vector page of ADR-0015 (`apps/desktop-web/epub/test/egress.html`,
    /// a test resource) is opened in the Mac's `WKWebView` through the scheme handler, the
    /// content rule list and the Content-Security-Policy header, and none of the eight reaches
    /// the repository's collector (`MockServers.egressPort`). The control opens the same page
    /// through the same handler with neither the list nor the header, and every vector
    /// arrives; without it an empty count would prove nothing. Task 4.5.
    @MainActor
    @Suite("EPUB egress")
    struct EpubEgressTests {
        @Test(
            "Unguarded, every one of the eight vectors reaches the collector",
            .enabled(if: MockServers.isEgressUp, "run `pnpm egress` in apps/desktop-web/epub first")
        )
        func control() async throws {
            let run = try await render(deny: false)
            #expect(run.served.contains { $0.hasPrefix("egress.html") }, "the page never loaded")
            let missing = Self.vectors.filter { !run.arrived.contains($0) }
            ConformanceLog.note("egress control", "\(run.arrived.count) of \(Self.vectors.count) arrived", wave: 4)
            #expect(missing.isEmpty, "unblocked, these should have arrived: \(missing)")
        }

        @Test(
            "With the rule list and the header, none of the eight arrives and the page is still served",
            .enabled(if: MockServers.isEgressUp, "run `pnpm egress` in apps/desktop-web/epub first")
        )
        func denied() async throws {
            let run = try await render(deny: true)
            #expect(run.served.contains { $0.hasPrefix("egress.html") }, "the page must still be served")
            #expect(run.attempts == Self.vectors.count, "the collector counts \(run.attempts) vectors")
            #expect(run.arrived.isEmpty, "these reached the network: \(run.arrived)")
            ConformanceLog.note("egress guarded", "\(run.arrived.count) of \(run.attempts) arrived", wave: 4)
        }

        @Test("The rules are rules WebKit accepts")
        func theListCompiles() async throws {
            let store = try #require(WKContentRuleListStore.default())
            let list = try await store.compileContentRuleList(
                forIdentifier: "app.storyarc.mac.publication-egress.test", encodedContentRuleList: EpubEgress.rules
            )
            #expect(list != nil)
        }

        /// The same eight, in the same order, as the page and the iOS suite's `Vector`.
        static let vectors = ["image", "scriptedImage", "fetch", "request", "beacon", "socket", "frame", "navigation"]

        /// How long the page gets to fire: the navigation vector leaves two seconds in and
        /// the iOS suite's slowest arrival was 3.2 seconds, so eight is the margin it keeps.
        private static let window: Duration = .seconds(8)

        private func render(deny: Bool) async throws -> EgressRun {
            try await Self.collector("/reset")
            let page = try Data(contentsOf: TestFixtures.egressPage)
            let handler = EpubSchemeHandler(source: EgressPageSource(page: page), sendsPolicy: deny)
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.setURLSchemeHandler(handler, forURLScheme: EpubEgress.scheme)
            if deny {
                await EpubEgress.prepare()
                try #require(EpubEgress.isPrepared, "the rule list did not compile")
                EpubEgress.deny(configuration.userContentController)
            }
            // In a window, sized and visible, as the reader's own web view is: a web view
            // outside any window is one WebKit may never start loading.
            let window = NSWindow(
                contentRect: NSRect(x: 200, y: 200, width: 600, height: 500),
                styleMask: [.titled, .closable], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            let webView = WKWebView(frame: window.contentLayoutRect, configuration: configuration)
            window.contentView = webView
            window.orderFront(nil)
            defer { window.close() }

            let base = EpubSchemeHandler.base(for: "egress")
            let url = try #require(URL(string: "\(base)egress.html?collector=\(MockServers.egressOrigin)"))
            webView.load(URLRequest(url: url))
            try await Task.sleep(for: Self.window)
            let count = try await Self.collector("/count")
            let body = try JSONSerialization.jsonObject(with: count) as? [String: Any]
            return EgressRun(
                served: handler.served,
                arrived: body?["arrived"] as? [String] ?? [],
                attempts: body?["attempts"] as? Int ?? 0
            )
        }

        /// One GET to the collector, from the host process rather than the page. An ephemeral
        /// session with a stamp on the URL: the shared session answered `/count` from its
        /// cache once, with the empty list of an earlier call, whatever the cache policy said.
        @discardableResult
        private static func collector(_ path: String) async throws -> Data {
            let stamp = "\(path.contains("?") ? "&" : "?")t=\(Date().timeIntervalSince1970)"
            let url = try #require(URL(string: MockServers.egressOrigin + path + stamp))
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            return try await URLSession(configuration: .ephemeral).data(for: request).0
        }
    }
}
