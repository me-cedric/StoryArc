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
/// arrives.
@MainActor
@Suite("Publication egress")
struct PublicationEgressTests {

    @Test("Every way out of the page reaches a host when nothing stops it")
    func control() async throws {
        let run = try await render(deny: false)

        #expect(run.served.contains { $0.hasSuffix("/style.css") }, "the page never loaded")
        #expect(run.reached == Vector.reachableNames, "unblocked, these should all arrive")
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

        /// What an unblocked page actually reaches from here.
        ///
        /// Not all eight. A frame and a top-level navigation to `https` never reach the
        /// listener from a `readium://` document in this harness, blocked or not — a
        /// WebKit behaviour that predates the rule list and one this test therefore
        /// cannot speak for. They stay in the page because they cost nothing to fire and
        /// the day WebKit does attempt them, ``denied`` is what has to keep holding.
        /// Android's mirror of this test does exercise both.
        static var reachable: [Vector] {
            [.image, .scriptedImage, .fetch, .request, .beacon, .socket]
        }

        static var reachableNames: [String] { reachable.map(\.rawValue).sorted() }
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
        // to be long enough that the control cannot pass for being slow.
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

/// Stands in for Readium's `WebViewServer`: serves the publication on the `readium`
/// scheme and nothing else.
@MainActor
private final class Origin: NSObject, WKURLSchemeHandler {
    private(set) var served: [String] = []
    private let page: String

    init(page: String) {
        self.page = page
        super.init()
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        served.append(url.absoluteString)
        let isStyle = url.path.hasSuffix(".css")
        let body = Data((isStyle ? "p{color:red}" : page).utf8)
        task.didReceive(
            URLResponse(
                url: url,
                mimeType: isStyle ? "text/css" : "text/html",
                expectedContentLength: body.count,
                textEncodingName: "utf-8"
            )
        )
        task.didReceive(body)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// A socket on loopback that records whether anything connected to it.
///
/// It answers nothing. A TCP connection is the whole evidence: the request never gets
/// as far as a reply, and a reply would only prove the same thing twice.
///
/// Plain BSD sockets rather than `NWListener`, which has a state machine to wait on and
/// hung this test when it never reported ready. `bind` either works or it does not, and
/// the port is readable the moment it has.
private final class Beacon: @unchecked Sendable {
    let name: String
    let port: UInt16

    private let descriptor: Int32
    private let lock = NSLock()
    private var reached = false

    var wasReached: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reached
    }

    init(name: String) throws {
        let handle = socket(AF_INET, SOCK_STREAM, 0)
        guard handle >= 0 else { throw BeaconFailure.noSocket }

        var reuse: Int32 = 1
        setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var wanted = sockaddr_in()
        wanted.sin_family = sa_family_t(AF_INET)
        wanted.sin_port = 0
        wanted.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian

        let bound = withUnsafePointer(to: &wanted) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(handle, 8) == 0 else {
            close(handle)
            throw BeaconFailure.noPort
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(handle, $0, &length)
            }
        }
        guard named == 0 else {
            close(handle)
            throw BeaconFailure.noPort
        }

        self.name = name
        descriptor = handle
        port = UInt16(bigEndian: assigned.sin_port)

        // Started once every member is set, so the thread may name `self`. Closing the
        // descriptor is what ends it.
        let thread = Thread { [weak self] in
            while true {
                let connection = accept(handle, nil, nil)
                if connection < 0 { return }
                close(connection)
                self?.mark()
            }
        }
        thread.stackSize = 64 * 1024
        thread.start()
    }

    private func mark() {
        lock.lock()
        reached = true
        lock.unlock()
    }

    /// Closing the descriptor is what ends the accepting thread.
    func stop() {
        close(descriptor)
    }
}

private enum BeaconFailure: Error {
    case noSocket
    case noPort
}
