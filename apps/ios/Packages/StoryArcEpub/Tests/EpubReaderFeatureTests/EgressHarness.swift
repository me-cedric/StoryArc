import Foundation
import WebKit

/// The machinery ``PublicationEgressTests`` fires its vectors at.
///
/// Split out of the suite so the assertions read as assertions. Nothing here knows
/// what is being proved; it serves a document on the publication's own scheme and
/// records which loopback ports something connected to.

/// Stands in for Readium's `WebViewServer`: serves the publication on the `readium`
/// scheme and nothing else.
@MainActor
final class Origin: NSObject, WKURLSchemeHandler {
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
final class Beacon: @unchecked Sendable {
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

enum BeaconFailure: Error {
    case noSocket
    case noPort
}
