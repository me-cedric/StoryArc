package app.storyarc.core.format

import java.net.HttpURLConnection
import java.net.URI
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * A publication read over HTTP `Range` requests.
 *
 * The third implementation ADR-0008 names, beside the local file and the network share. One
 * page of a 400 MB archive is the last ~64 KB to find the central directory, the directory
 * itself when it did not fit, and the entry's own bytes -- about 9 MB rather than 400, over
 * a transport that has had byte serving since 1999.
 *
 * Everything this type does beyond issuing the request is refusing answers. A range request
 * is a question with one correct reply and a great many plausible wrong ones: a proxy that
 * strips the header, a CDN that answers 200, a server whose `Content-Range` describes bytes
 * it did not send, a captive portal that redirects mid-stream. Each of those is a *case*
 * here, because "archive parsing runs on untrusted input" (SECURITY.md) does not stop being
 * true when the input arrives over a socket -- and because a page assembled from the wrong
 * bytes is worse than no page at all.
 *
 * What this type does **not** promise: that the bytes are the right bytes. HTTP gives a body
 * no identity, so a well-formed answer carrying some other window is invisible from here.
 * The container catches that, and `HttpSourceTest` pins both halves of the split.
 *
 * iOS's `HttpSource` is the same checks in the same order.
 */
class HttpSource internal constructor(
    private val url: String,
    /**
     * The total, learned from the `Content-Range` of the opening probe.
     *
     * Held rather than re-asked, and checked against every later answer: a total that
     * changes under a reader means the file was replaced while they were in it, which is a
     * different publication wearing the same address.
     */
    override val length: Long,
    private val transport: RangeTransport,
) : RandomAccessSource {

    companion object {
        /**
         * Opens a URL for ranged reading, or says why it cannot be read that way.
         *
         * The probe is `bytes=0-0`: one byte, which costs nothing and answers both questions
         * at once -- whether the server serves ranges at all, and how many bytes there are.
         * A `HEAD` would answer only the second, and plenty of servers answer `HEAD`
         * differently from `GET`.
         */
        suspend fun open(
            url: String,
            transport: RangeTransport = UrlConnectionRangeTransport(),
        ): HttpSource {
            val answer = transport.fetch(url, from = 0, through = 0)
            if (answer.url != url) throw HttpSourceException.Moved(answer.url)
            return when (answer.status) {
                206 -> {
                    val range = ContentRange.of(answer.contentRange)
                    if (range == null || range.total <= 0) throw HttpSourceException.UnknownLength
                    HttpSource(url, range.total, transport)
                }
                // The whole resource where one byte was asked for. Legal -- RFC 9110 lets a
                // server ignore a range it does not want to honour -- and useless for
                // streaming: every read would fetch the file. Downloading first is the
                // honest answer.
                200 -> throw HttpSourceException.NotRanged
                // Including 416: a resource that cannot satisfy `bytes=0-0` is one with no
                // first byte, and there is nothing here to open.
                else -> throw HttpSourceException.Refused(answer.status)
            }
        }

        /**
         * Registers `http` and `https` so a catalogue's acquisition URL opens by streaming.
         *
         * Called by the app rather than at class load: the app owns the decision, and it is
         * the only layer that can hand over a transport carrying a reader's credentials --
         * this module must not learn what a keystore is.
         */
        fun register(transport: () -> RangeTransport = { UrlConnectionRangeTransport() }) {
            for (scheme in listOf("http", "https")) {
                PublicationAccess.register(scheme) { path -> open(path, transport()) }
            }
        }
    }

    override suspend fun read(offset: Long, count: Int): ByteArray {
        if (offset < 0 || count < 0 || offset > length) {
            throw SourceOutOfBoundsException(offset, count, length)
        }
        // Clamped rather than refused, which is the contract every source keeps: fewer bytes
        // only at the end, never more. A parser that wants a short read to be an error asks
        // through `readExactly`.
        val wanted = minOf(count.toLong(), length - offset).toInt()
        if (wanted <= 0) return ByteArray(0)

        val answer = transport.fetch(url, from = offset, through = offset + wanted - 1)
        if (answer.url != url) throw HttpSourceException.Moved(answer.url)
        return when (answer.status) {
            206 -> partial(answer, offset, wanted)
            200 -> whole(answer, offset, wanted)
            // Bounds were checked above, so this is not the caller overreaching: the file
            // shrank, or was replaced, since the length was learned.
            416 -> throw HttpSourceException.LengthChanged(length)
            else -> throw HttpSourceException.Refused(answer.status)
        }
    }

    /** A 206, checked against the question it was supposed to be answering. */
    private fun partial(answer: HttpAnswer, offset: Long, wanted: Int): ByteArray {
        val range = ContentRange.of(answer.contentRange) ?: throw HttpSourceException.UnlabelledRange
        if (range.total != length) throw HttpSourceException.LengthChanged(length)
        // The window the server *says* it sent must be the window that was asked for.
        //
        // This is a check on the header and not on the bytes, and the difference is worth
        // being plain about: HTTP carries no identity for a body, so a server that sends the
        // wrong bytes under a correct `Content-Range` cannot be caught here at all. What
        // catches that is the container above -- signatures, offsets that must agree with
        // each other, a CRC per entry -- which is a second reason ADR-0008 was right to make
        // the ZIP reader ours rather than a library's.
        if (range.start != offset || range.end != offset + wanted - 1) {
            throw HttpSourceException.WrongRange(offset, range.start)
        }
        // A body that does not fill its own `Content-Range` is a truncated transfer. Never
        // padded to length: a page built out of zeroes is a page that looks like a bug in
        // the decoder rather than a broken link.
        if (answer.body.size != wanted) {
            throw HttpSourceException.ShortBody(wanted, answer.body.size)
        }
        return answer.body
    }

    /**
     * A 200 where a range was asked for: the server ignored it and sent everything.
     *
     * Wasteful rather than wrong, and worth honouring for the one read that matters -- the
     * probe already refused to open such a server, so this is a server that changed its mind
     * mid-publication, which a proxy waking up will do.
     */
    private fun whole(answer: HttpAnswer, offset: Long, wanted: Int): ByteArray {
        // The whole resource, or nothing. A 200 carrying only the requested slice is the
        // dangerous shape: the status says "all of it" and the bytes are a fragment, so a
        // reader that trusted the status would treat page 12 as the whole archive.
        if (answer.body.size.toLong() != length) {
            throw HttpSourceException.ShortBody(length.toInt(), answer.body.size)
        }
        val start = offset.toInt()
        return answer.body.copyOfRange(start, start + wanted)
    }
}

/**
 * Why a URL could not be read a range at a time.
 *
 * Every case means the same thing to a reader -- this cannot be streamed, so download it
 * first -- and different things to whoever has to fix it. `offline-downloads` requires the
 * app to state which happened rather than report a generic failure, and a source is grey and
 * never red: none of these is a dialog.
 */
sealed class HttpSourceException(message: String) : Exception(message) {
    /** The server sent the whole resource where one byte was asked for. */
    data object NotRanged : HttpSourceException("server does not serve ranges")

    /** A 206 with no `Content-Range` to check it against. */
    data object UnlabelledRange : HttpSourceException("206 with no Content-Range")

    /** A 206 whose `Content-Range` describes a different window than the one asked for. */
    data class WrongRange(val asked: Long, val got: Long) :
        HttpSourceException("asked for $asked, told $got")

    /**
     * Fewer bytes arrived than the answer promised -- a truncated transfer, or a link that
     * dropped mid-body.
     */
    data class ShortBody(val expected: Int, val got: Int) :
        HttpSourceException("expected $expected bytes, got $got")

    /**
     * The resource is not the size it was when it was opened. A different publication
     * wearing the same address.
     */
    data class LengthChanged(val was: Long) : HttpSourceException("length was $was")

    /** Nothing said how long the resource is, so no read can be sized. */
    data object UnknownLength : HttpSourceException("no length stated")

    /** The answer came from an address other than the one asked for. */
    data class Moved(val to: String) : HttpSourceException("answered from elsewhere")

    /** The server answered, unhappily. */
    data class Refused(val status: Int) : HttpSourceException("http $status")
}

/**
 * `bytes 0-15/4096`, parsed.
 *
 * Its own type because it is the only thing standing between a plausible answer and a
 * correct one, and because parsing it is exactly the kind of small total function a test can
 * pin every case of. iOS's `ContentRange` is the same parse.
 */
internal data class ContentRange(val start: Long, val end: Long, val total: Long) {
    companion object {
        /**
         * Null for a header that is absent, malformed, in a unit other than bytes, of
         * unknown total (`bytes 0-15/*`), or the 416 form (`bytes */4096`) -- none of which
         * describes bytes that arrived.
         */
        fun of(header: String?): ContentRange? {
            val parts = header?.trim()?.split(" ") ?: return null
            if (parts.size != 2 || !parts[0].equals("bytes", ignoreCase = true)) return null
            val sides = parts[1].split("/")
            if (sides.size != 2) return null
            val span = sides[0].split("-")
            if (span.size != 2) return null
            val start = span[0].toLongOrNull() ?: return null
            val end = span[1].toLongOrNull() ?: return null
            val total = sides[1].toLongOrNull() ?: return null
            if (start < 0 || end < start || total <= end) return null
            return ContentRange(start, end, total)
        }
    }
}

/**
 * One answer to one ranged request, in the shape [HttpSource] checks.
 *
 * Deliberately not an `HttpURLConnection`: the checks above are the interesting part of this
 * file, and a value type is what lets a test hand them a server that lies.
 */
data class HttpAnswer(
    val status: Int,
    val body: ByteArray,
    /**
     * `Content-Range`, verbatim and unparsed, because a header this type does not understand
     * must not become a header it silently ignores.
     */
    val contentRange: String? = null,
    /**
     * The address the answer actually came from, after any redirects the transport followed.
     * Compared against the address asked for.
     */
    val url: String,
) {
    // A data class over a `ByteArray` needs these written out: the generated ones compare
    // the array's identity, so two answers carrying the same bytes would differ.
    override fun equals(other: Any?): Boolean = this === other ||
        (
            other is HttpAnswer && status == other.status && url == other.url &&
                contentRange == other.contentRange && body.contentEquals(other.body)
            )

    override fun hashCode(): Int {
        var result = status
        result = 31 * result + body.contentHashCode()
        result = 31 * result + (contentRange?.hashCode() ?: 0)
        return 31 * result + url.hashCode()
    }
}

/**
 * One GET with a `Range` header.
 *
 * A seam rather than a hard call to `HttpURLConnection`, for two reasons: a test needs a
 * server that misbehaves on demand, and the app needs to attach a catalogue's credentials
 * without this module learning where they are kept.
 */
interface RangeTransport {
    /** Fetches [from]..[through] inclusive. Both ends are byte offsets, as `Range` counts. */
    suspend fun fetch(url: String, from: Long, through: Long): HttpAnswer
}

/**
 * The transport the app uses, over `HttpURLConnection`.
 *
 * `HttpURLConnection` rather than a new dependency, which is the same choice `core:catalogue`
 * made for the same reason: the app makes one kind of request, and the platform has done
 * that since API 1.
 */
class UrlConnectionRangeTransport(
    private val connectTimeoutMillis: Int = 15_000,
    private val readTimeoutMillis: Int = 30_000,
) : RangeTransport {

    override suspend fun fetch(url: String, from: Long, through: Long): HttpAnswer =
        withContext(Dispatchers.IO) {
            val connection = URI(url).toURL().openConnection() as HttpURLConnection
            try {
                connection.requestMethod = "GET"
                connection.setRequestProperty("Range", "bytes=$from-$through")
                // A cached 200 would answer a range request with the whole file forever.
                connection.useCaches = false
                connection.connectTimeout = connectTimeoutMillis
                connection.readTimeout = readTimeoutMillis
                val status = connection.responseCode
                val stream = if (status >= 400) connection.errorStream else connection.inputStream
                HttpAnswer(
                    status = status,
                    // `readBytes` and not a buffer sized from `Content-Length`: a length a
                    // stranger sent is not a number this app allocates from (ADR-0008).
                    body = stream?.use { it.readBytes() } ?: ByteArray(0),
                    contentRange = connection.getHeaderField("Content-Range"),
                    // `HttpURLConnection` follows redirects itself and reports where it ended
                    // up, which is the only way this layer can notice it was sent elsewhere.
                    url = connection.url?.toString() ?: url,
                )
            } finally {
                connection.disconnect()
            }
        }
}
