public import Foundation

/// Reads a response body as an OPDS feed, whichever of the two OPDS dialects it is.
///
/// `opds-catalog`: the app detects the version "from the response rather than requiring
/// the user to declare it". Nobody who has a catalogue URL knows whether their server
/// speaks Atom or JSON, and asking is a question with no good answer.
public enum OpdsDocument {
    /// Parses a body, using the declared content type as a hint and the bytes as the
    /// authority.
    ///
    /// The content type is only a hint on purpose. Servers that get it wrong are common:
    /// several return `text/xml` for an Atom feed and at least one returns
    /// `application/octet-stream` for both. The first non-whitespace byte is not wrong.
    public static func parse(
        _ data: Data,
        contentType: String? = nil,
        baseURL: URL
    ) throws -> OpdsFeed {
        guard let first = data.first(where: { !($0 == 0x20 || $0 == 0x09 || $0 == 0x0a || $0 == 0x0d) })
        else { throw OpdsError.empty }

        if first == UInt8(ascii: "{") {
            return try OpdsJson.parse(data, baseURL: baseURL)
        }
        if first == UInt8(ascii: "<") {
            // An HTML page is also angle-bracketed, and is what a misconfigured server or a
            // login wall returns. Named here rather than left to the Atom parser, which
            // would report a missing element and send the reader looking for the wrong
            // thing.
            if looksLikeHTML(data) { throw OpdsError.notAFeed(received: .html) }
            return try OpdsAtom.parse(data, baseURL: baseURL)
        }
        throw OpdsError.notAFeed(received: .unrecognised(contentType: contentType))
    }

    /// A possibly relative href, made absolute against the feed it came from.
    static func resolve(_ href: String, relativeTo base: URL) -> URL? {
        URL(string: href, relativeTo: base)?.absoluteURL
    }

    /// The same, for a search template, which is not a URL and must not become one.
    ///
    /// A template carries `{searchTerms}`, `URL` percent-encodes a brace on the way in, and
    /// a server handed `%7BsearchTerms%7D` searches for that literal string. So the braces
    /// are put back and the result stays a string — there is nothing to fetch until a term
    /// is substituted in.
    static func resolveTemplate(_ href: String, relativeTo base: URL) -> String? {
        guard let url = resolve(href, relativeTo: base) else { return nil }
        return url.absoluteString
            .replacingOccurrences(of: "%7B", with: "{")
            .replacingOccurrences(of: "%7D", with: "}")
    }

    /// Whether the body opens an HTML document rather than an XML one.
    ///
    /// Looks only at the head of the body: an Atom feed can legitimately *contain* the
    /// word `html`, in a summary or an XHTML content element, and scanning the whole
    /// document would call that page HTML.
    private static func looksLikeHTML(_ data: Data) -> Bool {
        let head = (String(bytes: data.prefix(512), encoding: .utf8) ?? "").lowercased()
        if head.contains("<!doctype html") || head.contains("<html") { return true }
        // An XML declaration followed by an XHTML root is still a page, not a feed.
        return head.contains("<?xml") && head.contains("xhtml")
    }
}

/// Why a URL did not yield a catalogue.
///
/// `opds-catalog`: when a URL "returns something that is not an OPDS feed", the app "says
/// what it received — an HTML page, a redirect, a 404 — instead of reporting a generic
/// failure". Each of those is a case here so the message can be written once and be true.
public enum OpdsError: Error, Equatable, Sendable {
    /// The response had no body.
    case empty

    /// The body parsed, but is not a catalogue.
    case notAFeed(received: Received)

    /// The body is the right dialect and is malformed.
    case malformed(reason: String)

    /// The server answered, unhappily.
    case http(status: Int)

    /// The server asked who is calling.
    case unauthorized(scheme: AuthenticationScheme?)

    /// What arrived instead of a feed.
    public enum Received: Equatable, Sendable {
        case html
        case unrecognised(contentType: String?)
    }

    /// How a 401 asked to be answered.
    ///
    /// `opds-catalog` requires support for "HTTP Basic and Bearer tokens", and the
    /// challenge is the only thing that says which one this server wants.
    public enum AuthenticationScheme: String, Equatable, Sendable {
        case basic
        case bearer

        /// Reads the scheme out of a `WWW-Authenticate` header.
        public init?(challenge: String) {
            let name = challenge
                .trimmingCharacters(in: .whitespaces)
                .prefix { !$0.isWhitespace }
                .lowercased()
            switch name {
            case "basic": self = .basic
            case "bearer": self = .bearer
            default: return nil
            }
        }
    }
}
