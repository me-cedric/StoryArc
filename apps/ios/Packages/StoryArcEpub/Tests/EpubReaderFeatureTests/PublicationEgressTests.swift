import Foundation
import Testing
import WebKit

@testable import EpubReaderFeature

/// Whether a publication can reach the network from inside the reader's web view.
///
/// ADR-0015. An EPUB is HTML, and HTML that is merely being read can still fetch: a
/// tracking pixel, a script's `fetch`, a `sendBeacon`, a socket, a frame, a redirect.
/// None of it needs the reader to touch anything, and the host on the other end learns
/// the device's address, the moment of reading and — through a URL the publication's
/// author chose — which book.
///
/// Hermetic: the listeners are sockets on the simulator's own loopback, so nothing
/// leaves the machine and the test needs no network. The beacons use `https` because
/// App Transport Security would refuse plain `http` before the rule list was ever
/// consulted, and the test would then pass without proving anything. The handshake
/// fails, there being no certificate; the connection is accepted first, which is the
/// whole question.
///
/// ``control`` is the half that fails against the code before ADR-0015: every vector
/// arrives. It is also what stops ``denied`` passing for the wrong reason — an empty
/// result means nothing unless the same page, through the same window, is known to
/// reach a host when the list is absent.
///
/// **Running it.** `pnpm test:ios:epub`, which needs a simulator; `swift test` cannot
/// build this package at all. That script passes `-collect-test-diagnostics never` on
/// purpose: a failing test otherwise sends `xcodebuild` off to collect a sysdiagnose
/// from the simulator, and that collection times out after **600 seconds**. It turns a
/// thirteen-second answer into an eleven-minute one at exactly the moment someone needs
/// it quickly — when the egress rule has just broken. Budget for it: the two rendering
/// tests take eight seconds each and run concurrently, which is what sets the floor for
/// the whole `StoryArcEpub` suite of 36 tests — nine seconds of testing, inside about
/// fifteen seconds of `xcodebuild` against a simulator that is already awake and a
/// minute against one that is not.
@MainActor
@Suite("Publication egress")
struct PublicationEgressTests {

    @Test("Every way out of the page reaches a host when nothing stops it")
    func control() async throws {
        let run = try await render(deny: false)

        #expect(run.served.contains { $0.hasSuffix("/style.css") }, "the page never loaded")
        let missing = Vector.mustReach.map(\.rawValue).filter { !run.reached.contains($0) }
        #expect(missing.isEmpty, "unblocked, every one of these should have arrived")
    }

    @Test("The rule list stops every one of them, and serves the book anyway")
    func denied() async throws {
        let run = try await render(deny: true)

        #expect(
            run.served.contains { $0.hasSuffix("/style.css") },
            "the publication's own resources must still be served"
        )
        #expect(run.reached.isEmpty, "nothing may reach the network")
    }

    @Test("The rules WebKit is given are rules WebKit accepts")
    func theListCompiles() async throws {
        let store = try #require(WKContentRuleListStore.default())
        let list = try await store.compileContentRuleList(
            forIdentifier: "app.storyarc.publication-egress.test",
            encodedContentRuleList: PublicationEgress.rules
        )
        #expect(list != nil)
    }

    // MARK: - Harness

    /// One way a page has of reaching a host. Each gets its own listener, so a run
    /// names what escaped rather than only counting it.
    enum Vector: String, CaseIterable {
        case image
        case scriptedImage
        case fetch
        case request
        case beacon
        case socket
        case frame
        case navigation

        /// The floor an unguarded run has to clear, and only the floor.
        ///
        /// These six reached their listener on every run measured — six runs, across
        /// an iOS 26.5 and an iOS 27.0 simulator on Xcode 26.6. ``frame`` and
        /// ``navigation`` are not among them, and not because they cannot arrive:
        /// both were seen to arrive, repeatedly, on both simulators. They are absent
        /// because they arrive only *sometimes*. A subframe load and a top-level
        /// redirect are slower than the other six — the redirect does not even fire
        /// until two seconds into an eight-second window — and on a loaded machine
        /// either can miss it.
        ///
        /// So the control asserts a floor rather than an exact set, which is the
        /// difference between this suite and the version that was red. That one
        /// asserted equality against these same six, with a comment claiming a frame
        /// and a navigation *never* arrive from a `readium://` document. They do, most
        /// runs, so equality failed most runs — and passed on the runs where the
        /// simulator happened to be slow enough. It was a test that told you about the
        /// machine's mood, not about the code.
        ///
        /// A vector arriving here that is not on this list is not a defect: it is one
        /// more thing ``denied`` has to block, and does — ``denied`` asserts nothing
        /// reaches, over all eight, and that is where a frame and a navigation are
        /// really covered. A vector on this list that stops arriving *is* a defect,
        /// because the control has then quietly stopped proving that much of
        /// ``denied``.
        static var mustReach: [Vector] {
            [.image, .scriptedImage, .fetch, .request, .beacon, .socket]
        }
    }

    private struct Run {
        let served: [String]
        let reached: [String]
    }

    private func render(deny: Bool) async throws -> Run {
        var beacons: [Vector: Beacon] = [:]
        for vector in Vector.allCases {
            beacons[vector] = try Beacon(name: vector.rawValue)
        }
        defer { beacons.values.forEach { $0.stop() } }

        let ports = beacons.mapValues(\.port)
        let handler = Origin(page: Self.page(ports: ports))
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "readium")
        let webView = WKWebView(frame: .zero, configuration: configuration)

        await PublicationEgress.prepare()
        guard let url = URL(string: "readium://5C0D-publication/index.xhtml") else {
            throw Failure.badURL
        }
        webView.load(URLRequest(url: url))
        // Deliberately after the load is issued. `EPUBSpreadView` loads its resource
        // inside its own initialiser, and the navigator calls `setupUserScripts` on the
        // controller only once that returns — so this test would be worthless if it
        // installed the list any earlier than the app can.
        if deny {
            PublicationEgress.deny(webView.configuration.userContentController)
        }

        // The beacons fire from a script, and the last of them is a navigation on a
        // timer. A refused connection is quicker than an accepted one, so the wait has
        // to be long enough that the control cannot pass for being slow. Both halves
        // share this window, which is the only thing that makes their two results
        // comparable — shorten it here and ``denied`` gets easier for free.
        try await Task.sleep(for: .seconds(8))

        return Run(
            served: handler.served,
            reached: beacons.values.filter(\.wasReached).map(\.name).sorted()
        )
    }

    private enum Failure: Error { case badURL }

    /// A page that tries every way out at once.
    private static func page(ports: [Vector: UInt16]) -> String {
        func host(_ vector: Vector) -> String { "https://127.0.0.1:\(ports[vector] ?? 0)" }
        return """
            <!doctype html><html><head>
            <link rel="stylesheet" href="readium://5C0D-publication/style.css">
            </head><body><p>text</p>
            <img src="\(host(.image))/pixel.png">
            <script>
            new Image().src = "\(host(.scriptedImage))/pixel.png";
            fetch("\(host(.fetch))/f").catch(function (e) {});
            var x = new XMLHttpRequest();
            x.open("GET", "\(host(.request))/x");
            try { x.send(); } catch (e) {}
            if (navigator.sendBeacon) {
              try { navigator.sendBeacon("\(host(.beacon))/b", "x"); } catch (e) {}
            }
            try { new WebSocket("wss://127.0.0.1:\(ports[.socket] ?? 0)/s"); } catch (e) {}
            var f = document.createElement("iframe");
            f.src = "\(host(.frame))/frame";
            document.body.appendChild(f);
            setTimeout(function () {
              location.href = "\(host(.navigation))/go";
            }, 2000);
            </script>
            </body></html>
            """
    }
}
