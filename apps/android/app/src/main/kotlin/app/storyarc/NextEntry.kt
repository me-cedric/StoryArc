package app.storyarc

import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import app.storyarc.core.model.Publication
import app.storyarc.feature.library.ServerListContext
import kotlinx.coroutines.launch

/**
 * Opens the entry a reader took from an end-of-publication offer.
 *
 * `collections-and-reading-lists` tasks 7.3 and 7.14: an entry with a file on this device
 * opens the way every publication does. The next entry of a server reading list has no file
 * until the list fetches it, so it is fetched the way the list screen fetches a row. A failed
 * fetch is said, because an offer that does nothing when taken tells the reader nothing.
 */
internal fun AppHost.openEntry(entry: Publication) {
    library.location(entry)?.let { return open(entry, it) }
    activity.lifecycleScope.launch {
        when (val fetched = ServerListContext.open(activity, entry, dependencies.progress)) {
            is ServerListContext.Fetch.Opened -> open(fetched.publication, fetched.path)
            is ServerListContext.Fetch.Failed ->
                Toast.makeText(activity, fetched.message, Toast.LENGTH_LONG).show()
            null -> Unit
        }
    }
}
