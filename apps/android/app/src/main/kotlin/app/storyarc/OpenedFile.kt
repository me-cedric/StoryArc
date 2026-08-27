package app.storyarc

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.IntentCompat
import app.storyarc.core.format.IndexException
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.format.UriSource
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationIdentity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * A publication the system handed to the app, and what to do with it.
 *
 * `local-library` requires StoryArc to "open a supported publication handed to it by the
 * system without requiring the user to configure a source first". The manifest already
 * declares intent filters, so the system offers StoryArc and hands the file over. Nothing
 * read `intent.data`, so every one of those files was dropped — the app showed its library
 * as if the reader had launched it themselves.
 *
 * Kept out of `MainActivity` because opening a handed-over file is three separate jobs:
 * reaching a provider's `Uri`, deciding what the bytes are, and saying so when they are
 * nothing StoryArc reads.
 */
internal object OpenedFile {

    /** What came of a file the system handed over. */
    sealed interface Outcome {
        data class Opened(val publication: Publication, val decoderPath: String) : Outcome

        /** The format was recognised and StoryArc does not read it. */
        data class Unsupported(val name: String, val detected: String) : Outcome

        /** The bytes could not be reached, or could not be understood at all. */
        data class Unreadable(val name: String) : Outcome
    }

    /** The `Uri` an intent carries, whether it arrived as data or as a stream extra. */
    fun uriFrom(intent: Intent?): Uri? = when (intent?.action) {
        Intent.ACTION_VIEW -> intent.data
        // A share sheet sends the file as an extra rather than as the intent's data, and
        // `local-library` names the share sheet as one of the three ways in.
        // `IntentCompat`, because the typed overload arrives at API 33 and ADR-0003
        // keeps the floor at 31.
        Intent.ACTION_SEND -> IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
        else -> null
    }

    /**
     * Indexes a handed-over file.
     *
     * The source stays open for the whole index, because the decoder path it exposes is
     * `/proc/self/fd/N` and that resolves only while the descriptor is open. The caller
     * gets the path back so the reader can open the same bytes without a copy.
     */
    suspend fun index(resolver: ContentResolver, uri: Uri): Outcome = withContext(Dispatchers.IO) {
        val name = displayName(resolver, uri)
        runCatching {
            UriSource(resolver, uri).use { source ->
                // A digest, not the `Uri`. A provider hands the same file over under a
                // different `Uri` each time, so an identity built from one would give the
                // reader a fresh reading position on every open. ADR-0006 puts the digest
                // second in its order of preference for exactly this case.
                val digest = PublicationIndexer.contentDigest(File(source.descriptorPath))
                val publication = PublicationIndexer.index(
                    source = source,
                    name = name,
                    identity = PublicationIdentity(contentDigest = digest),
                )
                Outcome.Opened(publication, source.descriptorPath)
            }
        }.getOrElse { error ->
            val detected = (error as? IndexException.Unsupported)?.format
            if (detected != null) Outcome.Unsupported(name, detected) else Outcome.Unreadable(name)
        }
    }

    /** The provider's own name for the file, which is the only name a reader recognises. */
    private fun displayName(resolver: ContentResolver, uri: Uri): String {
        resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst() && !cursor.isNull(0)) return cursor.getString(0)
        }
        return uri.lastPathSegment ?: "this file"
    }
}
