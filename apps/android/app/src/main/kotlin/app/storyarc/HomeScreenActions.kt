package app.storyarc

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import app.storyarc.core.model.Publication
import app.storyarc.core.model.QuickAction
import app.storyarc.core.model.QuickActionRequest
import app.storyarc.core.model.QuickActions

/**
 * The menu the launcher shows when the app icon is held down.
 *
 * `native-experience` names quick actions among the system affordances the app must use
 * rather than invent. Which entries the menu holds is decided by [QuickActions] in
 * `core:model`, mirrored by iOS; this file is only the platform's vocabulary for it.
 *
 * The entries survive the app being killed because the launcher, not the app, stores them.
 * That is also why the publication travels as an identifier in an intent extra rather than
 * as a path — a menu can be older than the scan that last placed the file, and a
 * `content://` grant does not outlive the process that was given it.
 */
internal object HomeScreenActions {

    /** The action every shortcut intent carries. A shortcut with no action is refused. */
    const val ACTION = "app.storyarc.action.QUICK_ACTION"

    /** Which entry was chosen, and — for the continue entry — which publication. */
    const val EXTRA_ACTION = "app.storyarc.extra.QUICK_ACTION"
    const val EXTRA_PUBLICATION = "app.storyarc.extra.PUBLICATION"

    /**
     * Replaces the menu with the entries the core says belong in it.
     *
     * A whole replacement rather than an edit: the list is short, it is derived from state
     * the app already holds, and a menu assembled by mutation is a menu that can hold two
     * continue entries for two different books.
     *
     * [context] must be the *activity's*, not the application's. `localization` lets a
     * reader override the interface language and that override lives on the activity's
     * context (see `InterfaceLanguage`); labels resolved against the application context
     * would come out in the system's language while the app was in the reader's.
     */
    fun publish(context: Context, continuing: Publication?, hasDownloads: Boolean) {
        val actions = QuickActions.offered(continuing, hasDownloads)
        ShortcutManagerCompat.setDynamicShortcuts(
            context,
            actions.mapIndexed { rank, action -> shortcut(context, action, rank) },
        )
    }

    /**
     * Says a publication was just opened, and republishes the menu around it.
     *
     * Android has no Handoff, and inventing a cross-device sync for it would need a backend
     * this app does not have and will not get. `pushDynamicShortcut` is the honest mirror:
     * it publishes the entry *and* reports it as used, which is what lets the launcher rank
     * it, the Assistant answer "continue reading", and the system offer it where it offers
     * predictions. The reporting is the whole point — a shortcut nobody has told the system
     * about is a shortcut the system will not surface.
     *
     * Called when a publication is opened rather than on a timer: that is the event, and
     * polling for it would be guessing.
     */
    fun reportOpened(context: Context, publication: Publication, hasDownloads: Boolean) {
        publish(context, publication, hasDownloads)
        val entry = QuickActions.offered(publication, hasDownloads)
            .firstOrNull { it is QuickAction.ContinueReading }
            ?: return
        ShortcutManagerCompat.pushDynamicShortcut(context, shortcut(context, entry, rank = 0))
    }

    /** What the reader chose, read back out of the intent the launcher sent. */
    fun requestFrom(intent: Intent?): QuickActionRequest? {
        if (intent?.action != ACTION) return null
        return QuickActionRequest.of(
            intent.getStringExtra(EXTRA_ACTION),
            intent.getStringExtra(EXTRA_PUBLICATION),
        )
    }

    private fun shortcut(context: Context, action: QuickAction, rank: Int): ShortcutInfoCompat {
        val intent = Intent(context, MainActivity::class.java)
            .setAction(ACTION)
            .putExtra(EXTRA_ACTION, action.id)
            // Onto the existing task rather than beside it. Without this a reader who taps
            // a quick action while the app is already open gets a second copy of it, and
            // the back gesture then walks out through a library they never opened.
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

        val (shortLabel, longLabel, icon) = when (action) {
            is QuickAction.ContinueReading -> {
                intent.putExtra(EXTRA_PUBLICATION, action.publicationId)
                Triple(
                    context.getString(R.string.shortcut_continue),
                    context.getString(R.string.shortcut_continue_named, action.title),
                    R.drawable.ic_shortcut_continue,
                )
            }
            QuickAction.Library -> Triple(
                context.getString(R.string.shortcut_library),
                context.getString(R.string.shortcut_library),
                R.drawable.ic_shortcut_library,
            )
            QuickAction.Downloads -> Triple(
                context.getString(R.string.shortcut_downloads),
                context.getString(R.string.shortcut_downloads),
                R.drawable.ic_shortcut_downloads,
            )
        }

        return ShortcutInfoCompat.Builder(context, action.id)
            .setShortLabel(shortLabel)
            .setLongLabel(longLabel)
            .setIcon(IconCompat.createWithResource(context, icon))
            .setRank(rank)
            .setIntent(intent)
            .build()
    }
}
