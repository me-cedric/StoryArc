public import Foundation

/// A publication read over HTTP `Range` requests.
///
/// The third implementation ADR-0008 names, beside the local file and the network share.
/// One page of a 400 MB archive is the last ~64 KB to find the central directory, the
/// directory itself when it did not fit, and the entry's own bytes — about 9 MB rather
/// than 400, over a transport that has had byte serving since 1999.
///
/// Everything this type does beyond issuing the request is refusing answers. A range
/// request is a question with one correct reply and a great many plausible wrong ones: a
/// proxy that strips the header, a CDN that answers 200, a server whose `Content-Range`
/// describes bytes it did not send, a captive portal that redirects mid-stream. Each of
/// those is a *case* here, because `archive parsing runs on untrusted input` (SECURITY.md)
/// does not stop being true when the input arrives over a socket — and because a page
/// assembled from the wrong bytes is worse than no page at all.
///
/// What this type does **not** promise: that the bytes are the right bytes. HTTP gives a
/// body no identity, so a well-formed answer carrying some other window is invisible from
/// here. The container catches that, and `HttpSourceTests` pins both halves of the split.
///
/// When an answer cannot be trusted this throws rather than guessing, and the caller falls
/// back to what the app already does: download the publication first. `offline-downloads`
/// requires that fallback to be stated rather than discovered, which is why
/// ``HttpSourceError`` names each reason.
public struct HttpSource: RandomAccessSource {
    /// The total, learned from the `Content-Range` of the opening probe.
    ///
    /// Held rather than re-asked, and checked against every later answer: a total that
    /// changes under a reader means the file was replaced while they were in it, which is a
    /// different publication wearing the same address.
    public let length: Int64

    private let url: URL
    private let transport: any RangeTransport

    init(url: URL, length: Int64, transport: any RangeTransport) {
        self.url = url
        self.length = length
        self.transport = transport
    }

    /// Opens a URL for ranged reading, or says why it cannot be read that way.
    ///
    /// The probe is `bytes=0-0`: one byte, which costs nothing and answers both questions at
    /// once — whether the server serves ranges at all, and how many bytes there are. A
    /// `HEAD` would answer only the second, and plenty of servers answer `HEAD` differently
    /// from `GET`.
    public static func open(
        _ url: URL,
        transport: any RangeTransport = UrlSessionRangeTransport()
    ) async throws -> HttpSource {
        let answer = try await transport.fetch(url, from: 0, through: 0)
        guard answer.url == url else { throw HttpSourceError.moved(to: answer.url) }
        switch answer.status {
        case 206:
            guard let range = ContentRange(answer.contentRange), range.total > 0 else {
                throw HttpSourceError.unknownLength
            }
            return HttpSource(url: url, length: range.total, transport: transport)
        case 200:
            // The whole resource where one byte was asked for. Legal — RFC 9110 lets a
            // server ignore a range it does not want to honour — and useless for streaming:
            // every read would fetch the file. Downloading first is the honest answer.
            throw HttpSourceError.notRanged
        // Including 416: a resource that cannot satisfy `bytes=0-0` is one with no first
        // byte, and there is nothing here to open.
        default:
            throw HttpSourceError.refused(status: answer.status)
        }
    }

    /// Registers `http` and `https` so a catalogue's acquisition URL opens by streaming.
    ///
    /// Called by the app rather than at load: the app owns the decision, and it is the only
    /// layer that can hand over a transport carrying a reader's credentials — this module
    /// must not learn what a keychain is.
    public static func register(
        transport: @autoclosure @escaping @Sendable () -> any RangeTransport =
            UrlSessionRangeTransport()
    ) {
        for scheme in ["http", "https"] {
            ComicArchiveOpener.register(scheme: scheme) { url in
                try await open(url, transport: transport())
            }
        }
    }

    public func read(offset: Int64, count: Int) async throws -> Data {
        guard HeaderBounds.span(offset: offset, count: 0, fitsIn: length), count >= 0 else {
            throw SourceError.outOfBounds(offset: offset, count: count, length: length)
        }
        // Clamped rather than refused, which is the contract every source keeps: fewer bytes
        // only at the end, never more. A parser asking past the end gets a short read and
        // decides for itself; `readExactly` is the one that turns that into an error.
        let wanted = Int(min(Int64(count), length - offset))
        guard wanted > 0 else { return Data() }

        let answer = try await transport.fetch(url, from: offset, through: offset + Int64(wanted) - 1)
        guard answer.url == url else { throw HttpSourceError.moved(to: answer.url) }
        switch answer.status {
        case 206:
            return try partial(answer, offset: offset, wanted: wanted)
        case 200:
            return try whole(answer, offset: offset, wanted: wanted)
        case 416:
            // Bounds were checked above, so this is not the caller overreaching: the file
            // shrank, or was replaced, since the length was learned.
            throw HttpSourceError.lengthChanged(was: length)
        default:
            throw HttpSourceError.refused(status: answer.status)
        }
    }

    /// A 206, checked against the question it was supposed to be answering.
    private func partial(_ answer: HttpAnswer, offset: Int64, wanted: Int) throws -> Data {
        guard let range = ContentRange(answer.contentRange) else {
            throw HttpSourceError.unlabelledRange
        }
        guard range.total == length else { throw HttpSourceError.lengthChanged(was: length) }
        // The window the server *says* it sent must be the window that was asked for.
        //
        // This is a check on the header and not on the bytes, and the difference is worth
        // being plain about: HTTP carries no identity for a body, so a server that sends
        // the wrong bytes under a correct `Content-Range` cannot be caught here at all.
        // What catches that is the container above — signatures, offsets that must agree
        // with each other, a CRC per entry — which is a second reason ADR-0008 was right to
        // make the ZIP reader ours rather than a library's.
        guard range.start == offset, range.end == offset + Int64(wanted) - 1 else {
            throw HttpSourceError.wrongRange(asked: offset, got: range.start)
        }
        // A body that does not fill its own `Content-Range` is a truncated transfer. Never
        // padded to length: a page built out of zeroes is a page that looks like a bug in
        // the decoder rather than a broken link.
        guard answer.body.count == wanted else {
            throw HttpSourceError.shortBody(expected: wanted, got: answer.body.count)
        }
        return answer.body
    }

    /// A 200 where a range was asked for: the server ignored it and sent everything.
    ///
    /// Wasteful rather than wrong, and worth honouring for the one read that matters — the
    /// probe already refused to open such a server, so this is a server that changed its
    /// mind mid-publication, which a proxy waking up will do.
    private func whole(_ answer: HttpAnswer, offset: Int64, wanted: Int) throws -> Data {
        // The whole resource, or nothing. A 200 carrying only the requested slice is the
        // dangerous shape: the status says "all of it" and the bytes are a fragment, so a
        // reader that trusted the status would treat page 12 as the whole archive.
        guard answer.body.count == Int(length) else {
            throw HttpSourceError.shortBody(expected: Int(length), got: answer.body.count)
        }
        let start = Int(offset)
        return answer.body.subdata(in: start..<(start + wanted))
    }
}

/// Why a URL could not be read a range at a time.
///
/// Every case means the same thing to a reader — this cannot be streamed, so download it
/// first — and different things to whoever has to fix it. `offline-downloads` requires the
/// app to state which happened rather than report a generic failure, and a source is grey
/// and never red: none of these is a modal.
public enum HttpSourceError: Error, Equatable {
    /// The server sent the whole resource where one byte was asked for.
    case notRanged
    /// A 206 with no `Content-Range` to check it against.
    case unlabelledRange
    /// A 206 whose `Content-Range` describes a different window than the one asked for.
    case wrongRange(asked: Int64, got: Int64)
    /// Fewer bytes arrived than the answer promised — a truncated transfer, or a link that
    /// dropped mid-body.
    case shortBody(expected: Int, got: Int)
    /// The resource is not the size it was when it was opened. A different publication
    /// wearing the same address.
    case lengthChanged(was: Int64)
    /// Nothing said how long the resource is, so no read can be sized.
    case unknownLength
    /// The answer came from an address other than the one asked for.
    case moved(to: URL)
    /// The server answered, unhappily.
    case refused(status: Int)
}

/// `bytes 0-15/4096`, parsed.
///
/// Its own type because it is the only thing standing between a plausible answer and a
/// correct one, and because parsing it is exactly the kind of small total function a test
/// can pin every case of.
struct ContentRange: Equatable {
    let start: Int64
    let end: Int64
    let total: Int64

    /// Nil for a header that is absent, malformed, in a unit other than bytes, of unknown
    /// total (`bytes 0-15/*`), or the 416 form (`bytes */4096`) — none of which describes
    /// bytes that arrived.
    init?(_ header: String?) {
        guard let header else { return nil }
        let parts = header.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard parts.count == 2, parts[0].lowercased() == "bytes" else { return nil }
        let sides = parts[1].split(separator: "/", omittingEmptySubsequences: false)
        guard sides.count == 2 else { return nil }
        let span = sides[0].split(separator: "-", omittingEmptySubsequences: false)
        guard span.count == 2,
              let start = Int64(span[0]),
              let end = Int64(span[1]),
              let total = Int64(sides[1]),
              start >= 0, end >= start, total > end
        else { return nil }
        self.start = start
        self.end = end
        self.total = total
    }
}

/// One answer to one ranged request, in the shape ``HttpSource`` checks.
///
/// Deliberately not `HTTPURLResponse`: the checks above are the interesting part of this
/// file, and a value type is what lets a test hand them a server that lies.
public struct HttpAnswer: Sendable, Equatable {
    public let status: Int
    public let body: Data
    /// `Content-Range`, verbatim and unparsed, because a header this type does not
    /// understand must not become a header it silently ignores.
    public let contentRange: String?
    /// The address the answer actually came from, after any redirects the transport
    /// followed. Compared against the address asked for.
    public let url: URL

    public init(status: Int, body: Data, contentRange: String? = nil, url: URL) {
        self.status = status
        self.body = body
        self.contentRange = contentRange
        self.url = url
    }
}

/// One GET with a `Range` header.
///
/// A seam rather than a hard call to `URLSession`, for two reasons: a test needs a server
/// that misbehaves on demand, and the app needs to attach a catalogue's credentials without
/// this module learning where they are kept.
public protocol RangeTransport: Sendable {
    /// Fetches `from...through` inclusive. Both ends are byte offsets, as `Range` counts.
    func fetch(_ url: URL, from: Int64, through: Int64) async throws -> HttpAnswer
}

/// The transport the app uses, over `URLSession`.
public struct UrlSessionRangeTransport: RangeTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(_ url: URL, from: Int64, through: Int64) async throws -> HttpAnswer {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(from)-\(through)", forHTTPHeaderField: "Range")
        // A cached 200 would answer a range request with the whole file forever.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SourceError.unreadable }
        return HttpAnswer(
            status: http.statusCode,
            body: body,
            contentRange: http.value(forHTTPHeaderField: "Content-Range"),
            // `URLSession` follows redirects itself and reports where it ended up, which is
            // the only way this layer can notice that it was sent somewhere else.
            url: http.url ?? url
        )
    }
}
