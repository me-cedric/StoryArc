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
/// **Each run opens the web view before it measures it.** WebKit starts no networking
/// process until a page asks for the network, and that start costs whatever the machine
/// can spare. Measured on 2026-09-06, with the first load unmeasured, all eight vectors
/// arrive 0.3 to 3.3 seconds into the window; without it they arrived at 4.2 to 5.7
/// seconds on a simulator that had just booted, and on one run at over 8 seconds — past
/// the end of the window, so ``control`` reported every vector missing at once and the
/// rule was left proven in neither direction. That signature — every vector missing
/// together, while the page's own `style.css` was served — means the window expired,
/// not that egress stopped. See ``render(deny:)``.
///
/// **A killed run looks different, and is not a regression.** The two rendering tests
/// are the longest in the package, so a machine short of resources kills this run before
/// any other. `xcodebuild` then names both under `Failing tests:` and records no issue
/// against either. A real egress regression fails one test, names it, and prints the
/// vectors it expected. Nothing recorded means nothing was measured: run it again, and
/// without `-quiet`, which is what hides the reason the kill was reported with.
///
/// **Running it.** `pnpm test:ios:epub`, which needs a simulator; `swift test` cannot
/// build this package at all. That script passes `-collect-test-diagnostics never` on
/// purpose: a failing test otherwise sends `xcodebuild` off to collect a sysdiagnose
/// from the simulator, and that collection times out after **600 seconds**. It turns a
/// thirteen-second answer into an eleven-minute one at exactly the moment someone needs
/// it quickly — when the egress rule has just broken. Budget for it: the two rendering
/// tests run concurrently and each takes the opening load plus an eight-second window,
/// which is what sets the floor for the whole `StoryArcEpub` suite — 12.5 to 18.8
/// seconds of testing over eight measured runs on 2026-09-06, inside thirty to forty
/// seconds of `xcodebuild` against a simulator that is already awake, and a minute
/// against one that is not.
@MainActor
@Suite("Publication egress")
struct PublicationEgressTests {

    @Test("Every way out of the page reaches a host when nothing stops it")
    func control() async throws {
        let run = try await render(deny: false)

        #expect(run.served.contains { $0.hasSuffix("/style.css") }, "the page never loaded")
        let missing = Vector.allCases.map(\.rawValue).filter { !run.reached.contains($0) }
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
    ///
    /// ``control`` requires all eight, which is the whole set ``denied`` forbids. The
    /// two halves therefore make the same claim about the same vectors, in opposite
    /// directions, and no vector is forbidden without first being shown to arrive.
    ///
    /// It required only six until 2026-09-06, and excluded ``frame`` and ``navigation``
    /// on the ground that a subframe load and a top-level redirect were slower than the
    /// rest and missed the window on a loaded machine. The opening load removed that
    /// cause. It pays the networking process's start before the window opens, so the
    /// window measures the page rather than a daemon.
    ///
    /// Measured on 2026-09-06, over three runs with the opening load in place. All
    /// eight arrived on every run. The six quick ones arrived 0.3 to 2.3 seconds into
    /// the window and ``frame`` arrived at 0.9 to 1.9 seconds. ``navigation`` is the
    /// slowest, because the page fires it on a two-second timer: it arrived at 2.5,
    /// 2.7 and 3.2 seconds. The window is eight seconds, so the margin over the
    /// slowest arrival is a factor of 2.5.
    ///
    /// A vector that stops arriving here *is* a defect, even though ``denied`` still
    /// passes. The control has then quietly stopped proving that much of ``denied``,
    /// and an empty result is also what a broken vector looks like.
    enum Vector: String, CaseIterable {
        case image
        case scriptedImage
        case fetch
        case request
        case beacon
        case socket
        case frame
        case navigation
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

        let opener = try Beacon(name: "opener")
        defer { opener.stop() }

        let ports = beacons.mapValues(\.port)
        let handler = Origin(page: Self.page(ports: ports), opener: Self.openerPage(port: opener.port))
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "readium")
        let webView = WKWebView(frame: .zero, configuration: configuration)

        await PublicationEgress.prepare()
        guard
            let openerURL = URL(string: "readium://5C0D-publication/\(Origin.openerPath)"),
            let url = URL(string: "readium://5C0D-publication/index.xhtml")
        else {
            throw Failure.badURL
        }

        // The first load is not measured. WebKit starts no networking process until a
        // page asks for the network, and starting it costs whatever the machine can
        // spare: 1.4 seconds on a warm simulator, over 8 seconds on one that has just
        // booted. That cost used to fall inside the measured window, so ``control`` was
        // a race against a daemon rather than a reading of the page — and on 2026-09-06
        // it lost that race and reported all six vectors missing at once, which is the
        // signature of the window expiring rather than of egress being stopped. This
        // load pays the cost first; the window that follows measures the page.
        //
        // Twelve seconds, not sixty and not six. A run that hangs is killed, and the
        // kill names nothing. Measured on 2026-09-06, over fifteen starts on a machine
        // running four other build agents: the median start took 4.5 seconds, eleven
        // took under 6, and the slowest took 10.2 seconds. That slowest start went on
        // to pass, all eight vectors arriving inside the window that followed.
        //
        // So do not cut this ceiling to shorten the run. A start of 10.2 seconds is a
        // run that works, and a ceiling under it turns that run into a
        // ``Failure/networkNeverStarted`` that names a fault the code does not have. A
        // wrong red costs more than a slow green. Twelve clears the slowest start
        // measured and still fires long before a run could sit here for a minute.
        webView.load(URLRequest(url: openerURL))
        guard try await arrived(at: opener, within: .seconds(12)) else {
            throw Failure.networkNeverStarted
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
        // comparable — shorten it here and ``denied`` gets easier for free. The
        // slowest vector measured on 2026-09-06 was the redirect, at 3.2 seconds, so
        // eight seconds is a margin of 2.5 and not padding.
        try await Task.sleep(for: .seconds(8))

        return Run(
            served: handler.served,
            reached: beacons.values.filter(\.wasReached).map(\.name).sorted()
        )
    }

    /// Polls until the beacon is reached, or the ceiling passes.
    private func arrived(at beacon: Beacon, within ceiling: Duration) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: ceiling)
        while ContinuousClock.now < deadline {
            if beacon.wasReached { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return beacon.wasReached
    }

    private enum Failure: Error {
        case badURL
        /// The web view never reached loopback at all, so the measured window would
        /// prove nothing in either direction. Read the suite's note before changing it.
        case networkNeverStarted
    }

    /// A page whose only job is to make the web view start its networking process.
    ///
    /// It touches the opener's own listener and nothing else, so a vector cannot be
    /// recorded before the measured window opens.
    private static func openerPage(port: UInt16) -> String {
        """
        <!doctype html><html><body><script>
        fetch("https://127.0.0.1:\(port)/opener").catch(function (e) {});
        </script></body></html>
        """
    }

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
