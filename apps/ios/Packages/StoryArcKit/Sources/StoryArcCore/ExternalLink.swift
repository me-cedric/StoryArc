public import Foundation

/// A link out of a publication, and where it says it goes.
///
/// A book is untrusted input, and `ebook-reader` hands an external link to the system
/// rather than opening it over the text. Handed *anything*, that is a publication choosing
/// which installed app runs and with which parameters: `<a href="someapp://action?x=y">`
/// under innocuous link text, tapped once. So only the web is accepted, and the host is
/// carried out with it so the reader can be told where they are about to go.
///
/// A domain rule rather than a rendering one, which is why it lives here and not in the
/// EPUB reader: it is testable on the host, and both readers ask the same question.
///
/// Android's `ExternalLink` is the same type.
public struct ExternalLink: Sendable, Equatable {
    /// The address, unchanged. Only ever `http` or `https`.
    public let url: URL

    /// The host as a reader would read it, for the sentence that asks them.
    ///
    /// `www.` is dropped because it is not information: a confirmation that says
    /// "www.example.com" and one that says "example.com" describe the same destination, and
    /// the shorter one is the one somebody actually reads.
    public let host: String

    /// Nil for anything that is not a web address — which is the whole point.
    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host()?.lowercased(), !host.isEmpty
        else { return nil }
        self.url = url
        self.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
