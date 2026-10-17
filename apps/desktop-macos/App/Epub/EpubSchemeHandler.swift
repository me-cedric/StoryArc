import Foundation
import WebKit

/// One resource the scheme handler answers: the bytes and what they are.
struct EpubResource: Sendable {
    let data: Data
    let mimeType: String
}

/// Where the scheme handler gets its bytes: the open publication, or a test's page.
protocol EpubResourceSource: Sendable {
    /// The resource at a container path such as `OEBPS/ch1.xhtml`, or `nil` for none.
    func resource(at path: String) async -> EpubResource?
}

/// Serves a publication to the web view on the app's own scheme.
///
/// `design.md` Decision 6: `WKURLSchemeHandler` on a per-publication scheme serves the
/// archive's bytes, and every response carries the Content-Security-Policy header of
/// `EpubEgress`. The URL's host names the publication and its path is the container path,
/// so the Readium Web Publication Manifest's relative hrefs resolve to the archive's own
/// entries. A task the web view stops is never answered after that, which WebKit treats as
/// a fault. Task 4.5.
@MainActor
final class EpubSchemeHandler: NSObject, WKURLSchemeHandler {
    private let source: any EpubResourceSource
    /// Whether responses carry the Content-Security-Policy header. Always, except for the
    /// egress test's control, which measures the page with nothing in its way.
    private let sendsPolicy: Bool
    /// Tasks still being answered, so a stopped one is dropped rather than completed.
    private var inFlight: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Every path asked for, in order, for the tests and the walks.
    private(set) var served: [String] = []

    init(source: any EpubResourceSource, sendsPolicy: Bool = true) {
        self.source = source
        self.sendsPolicy = sendsPolicy
    }

    /// The scheme's root for one publication.
    nonisolated static func base(for token: String) -> String { "\(EpubEgress.scheme)://\(token)/" }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = String(url.path(percentEncoded: false).drop(while: { $0 == "/" }))
        served.append(path)
        let id = ObjectIdentifier(task)
        let source = self.source
        inFlight[id] = Task { [weak self] in
            let resource = await source.resource(at: path)
            guard let self, inFlight[id] != nil else { return }
            inFlight[id] = nil
            Self.answer(task, url: url, with: resource, policy: sendsPolicy)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        inFlight[id]?.cancel()
        inFlight[id] = nil
    }

    private static func answer(_ task: any WKURLSchemeTask, url: URL, with resource: EpubResource?, policy: Bool) {
        let body = resource?.data ?? Data()
        var headers = [
            "Content-Type": resource?.mimeType ?? "text/plain",
            "Content-Length": String(body.count),
            "Cache-Control": "no-store",
            "Access-Control-Allow-Origin": "*",
        ]
        if policy { headers["Content-Security-Policy"] = EpubEgress.contentSecurityPolicy }
        guard let response = HTTPURLResponse(
            url: url, statusCode: resource == nil ? 404 : 200, httpVersion: "HTTP/1.1", headerFields: headers
        ) else { return }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }
}

/// The media type a container path's extension names, for the response header.
enum EpubMediaTypes {
    static let byExtension: [String: String] = [
        "xhtml": "application/xhtml+xml", "html": "text/html", "htm": "text/html",
        "css": "text/css", "js": "text/javascript", "json": "application/json",
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
        "svg": "image/svg+xml", "webp": "image/webp", "avif": "image/avif",
        "ttf": "font/ttf", "otf": "font/otf", "woff": "font/woff", "woff2": "font/woff2",
        "mp3": "audio/mpeg", "m4a": "audio/mp4", "mp4": "video/mp4", "ogg": "audio/ogg",
        "ncx": "application/x-dtbncx+xml", "opf": "application/oebps-package+xml", "xml": "application/xml",
    ]

    static func type(of path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        return byExtension[ext] ?? "application/octet-stream"
    }
}
