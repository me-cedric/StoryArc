public import Foundation
internal import StoryArcCore

/// One cover request, sent so that it can reach only a listed host and read only so much.
///
/// `AGENTS.md` non-negotiable 2. A redirect is refused unless it lands on a host
/// ``CoverImageHosts`` lists, by a task delegate that answers before the redirect is
/// followed — checking the final address afterwards would be checking a request that already
/// left. And an answer larger than ``maxBytes`` is refused rather than held whole: an answer is
/// untrusted input. Android's `PlatformCoverTransport` does the same two things.
enum CoverFetch {

    /// The largest answer read. A cover is not 8 MB.
    static let maxBytes = 8 * 1024 * 1024

    static func send(_ request: URLRequest, in session: URLSession) async -> (Data, HTTPURLResponse)? {
        guard CoverImageHosts.allows(request.url),
              let (bytes, response) = try? await session.bytes(for: request, delegate: RedirectGuard.shared),
              let http = response as? HTTPURLResponse,
              http.expectedContentLength <= maxBytes
        else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { return nil }
            }
        } catch {
            return nil
        }
        return (data, http)
    }
}

/// Refuses a redirect to a host ``CoverImageHosts`` does not list.
final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = RedirectGuard()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        CoverImageHosts.allows(request.url) ? request : nil
    }
}
