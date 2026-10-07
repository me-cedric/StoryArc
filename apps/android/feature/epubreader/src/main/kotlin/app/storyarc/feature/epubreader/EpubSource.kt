package app.storyarc.feature.epubreader

import android.content.Context
import android.net.Uri
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.format.RandomAccessSource
import app.storyarc.core.format.readExactly
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.Error
import org.readium.r2.shared.util.ThrowableError
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.asset.Asset
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.data.AccessError
import org.readium.r2.shared.util.data.ReadError
import org.readium.r2.shared.util.format.FormatHints
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.mediatype.MediaType
import org.readium.r2.shared.util.resource.Resource
import org.readium.r2.shared.util.resource.filename
import org.readium.r2.shared.util.toAbsoluteUrl
import org.readium.r2.shared.util.toUrl
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser
import java.io.File

/** What opening a book came to. Each failure has its own sentence on the screen. */
internal sealed interface EpubOpening {
    data class Opened(val publication: Publication) : EpubOpening

    data object Unreachable : EpubOpening

    data object Unreadable : EpubOpening
}

/**
 * Opens the book at [location] through Readium.
 *
 * Two steps, both Readium's: an `AssetRetriever` reaches the bytes, and a `PublicationOpener`
 * parses them. A book on a share or a server streams: Readium reads its ZIP through
 * [SourceResource], one range at a time, and never fetches the whole file
 * (`publication-formats`, *Streaming capability per format*).
 */
internal suspend fun openEpub(context: Context, location: String): EpubOpening {
    val httpClient = DefaultHttpClient()
    val assetRetriever = AssetRetriever(context.contentResolver, httpClient)
    val asset = retrieveEpub(assetRetriever, location) ?: return EpubOpening.Unreachable
    val opener = PublicationOpener(
        DefaultPublicationParser(
            context = context,
            httpClient = httpClient,
            assetRetriever = assetRetriever,
            // No PDF factory: a PDF opens in the comic reader, which renders it with the
            // platform's own `PdfRenderer`. Wiring a second PDF engine in here would ship two.
            pdfFactory = null,
        ),
    )
    return opener.open(asset, allowUserInteraction = false)
        .getOrElse { return EpubOpening.Unreadable }
        .let(EpubOpening::Opened)
}

private suspend fun retrieveEpub(assetRetriever: AssetRetriever, location: String): Asset? {
    if (PublicationAccess.isRemote(location)) {
        val source = runCatching { PublicationAccess.remoteSource(location) }.getOrNull() ?: return null
        val resource = SourceResource(source, location.substringAfterLast('/'))
        return assetRetriever.retrieve(resource, FormatHints(mediaType = MediaType.EPUB)).getOrElse {
            resource.close()
            return null
        }
    }
    val url: AbsoluteUrl =
        if (location.startsWith("content://")) {
            Uri.parse(location).toAbsoluteUrl()
        } else {
            File(location).toUrl(isDirectory = false)
        } ?: return null
    return assetRetriever.retrieve(url).getOrElse { return null }
}

/**
 * A Readium resource that reads through a ranged source.
 *
 * It has no URL, so Readium's ZIP opener takes its streaming path rather than its file path.
 * Each read is one ranged read of the source, clamped to its length.
 */
internal class SourceResource(
    private val source: RandomAccessSource,
    private val name: String,
) : Resource {

    override val sourceUrl: AbsoluteUrl? = null

    override suspend fun properties(): Try<Resource.Properties, ReadError> =
        Try.success(Resource.Properties { filename = name })

    override suspend fun length(): Try<Long, ReadError> = Try.success(source.length)

    override suspend fun read(range: LongRange?): Try<ByteArray, ReadError> =
        try {
            val start = (range?.first ?: 0L).coerceIn(0L, source.length)
            val end = (range?.let { it.last + 1 } ?: source.length).coerceIn(start, source.length)
            Try.success(if (end == start) ByteArray(0) else source.readExactly(start, (end - start).toInt()))
        } catch (cause: Exception) {
            Try.failure(ReadError.Access(SourceAccessError(cause)))
        }

    override fun close() = source.close()
}

/** A source that would not answer, in the shape Readium reports a failed read. */
private class SourceAccessError(exception: Exception) : AccessError {
    override val message: String = exception.message ?: "the source could not be read"
    override val cause: Error = ThrowableError(exception)
}
