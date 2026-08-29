package app.storyarc.feature.library

import android.content.ContentResolver
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper

/**
 * Notices when a watched folder's contents change.
 *
 * `local-library`: a file added to a watched folder "appears in the library within 10 seconds
 * without a manual refresh". The provider is asked to say so rather than the app polling for
 * it -- a poll over ten thousand documents would cost more than the change it is looking for.
 *
 * One observer per picked folder, and no more: a tree registration with
 * `notifyForDescendants` set already carries everything under it, which is what a
 * `DocumentsProvider` notifies on when a document is written or deleted. iOS needs one
 * kernel source per *directory* for the same coverage, because a vnode event says nothing
 * about what happened a level down; its `FolderWatcher` says so and caps how many it opens.
 * The mechanisms have nothing in common. What mirrors is [FolderSnapshot], which decides
 * what a change *means*.
 *
 * A provider is free to say nothing at all -- some report no change until their own sync
 * finishes -- so this is never the only way a change is found. Returning to the foreground
 * reconciles as well, which is the other scenario the requirement names.
 */
internal class FolderWatcher(private val resolver: ContentResolver) {

    private val handler = Handler(Looper.getMainLooper())
    private val observers = mutableMapOf<Uri, ContentObserver>()
    private var coalesce: Runnable? = null

    /** Watches these folders, replacing whatever was watched before. */
    fun watch(trees: List<Uri>, onChange: () -> Unit) {
        stop()
        for (tree in trees) {
            val observer = object : ContentObserver(handler) {
                override fun onChange(selfChange: Boolean, uri: Uri?) = schedule(onChange)
            }
            runCatching { resolver.registerContentObserver(tree, true, observer) }
                .onSuccess { observers[tree] = observer }
        }
    }

    /** Stops watching. The library stays; only the registrations go. */
    fun stop() {
        coalesce?.let(handler::removeCallbacks)
        coalesce = null
        for (observer in observers.values) {
            runCatching { resolver.unregisterContentObserver(observer) }
        }
        observers.clear()
    }

    /**
     * Coalesces a burst into one reconcile.
     *
     * Copying a folder of forty comics in produces forty notifications, and reconciling on
     * each would walk the tree forty times to notice one arrival at a time. A second's wait
     * is invisible against the ten the requirement allows.
     */
    private fun schedule(onChange: () -> Unit) {
        coalesce?.let(handler::removeCallbacks)
        val run = Runnable { onChange() }
        coalesce = run
        handler.postDelayed(run, COALESCE_MILLIS)
    }

    private companion object {
        const val COALESCE_MILLIS = 1_000L
    }
}
