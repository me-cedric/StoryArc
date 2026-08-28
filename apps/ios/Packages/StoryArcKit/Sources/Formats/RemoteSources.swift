public import Foundation

internal import Synchronization

extension ComicArchiveOpener {
    /// How to reach a URL this module knows nothing about.
    ///
    /// A share's URL is `smb://…`, and teaching this module to open one would point the
    /// dependency the wrong way — `Formats` would have to know about `Smb`. Instead the app
    /// registers an opener for the scheme, and the branch below stays one line.
    ///
    /// A `Mutex` rather than a plain dictionary: registration happens once at launch, but
    /// the reads come from whichever task is opening a publication.
    private static let remote = Mutex<[String: @Sendable (URL) async throws -> any RandomAccessSource]>([:])

    /// Registers how to open a URL with the given scheme, such as `smb`.
    public static func register(
        scheme: String,
        opener: @escaping @Sendable (URL) async throws -> any RandomAccessSource
    ) {
        remote.withLock { $0[scheme] = opener }
    }

    /// Whether a URL belongs to a registered remote scheme.
    public static func isRemote(_ url: URL) -> Bool {
        guard let scheme = url.scheme else { return false }
        return remote.withLock { $0[scheme] != nil }
    }

    /// The source behind a remote URL, when one is registered.
    public static func source(for url: URL) async throws -> (any RandomAccessSource)? {
        guard let scheme = url.scheme,
              let opener = remote.withLock({ $0[scheme] })
        else { return nil }
        return try await opener(url)
    }

}
