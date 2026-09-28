package app.storyarc

import android.content.Context
import android.content.Intent
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.QuickAction
import app.storyarc.core.model.QuickActionRequest
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The menu Android's launcher stores, which is the platform half of the quick actions.
 *
 * `QuickActionsTest` in `:core:model` owns the *list* — which entries the menu holds, in
 * which order — and iOS asserts the same table. This file owns what Android then does with
 * that list, and until now nothing did: `HomeScreenActions.kt` had no test of any kind, so
 * the labels, the icons, the ranks, the intent the launcher sends back, and the round trip
 * between publishing an entry and reading it back were all unasserted.
 *
 * The shortcuts are read back out of the platform's own store rather than out of a double.
 * `ShortcutManagerCompat.getDynamicShortcuts` returns what `setDynamicShortcuts` put there,
 * so every assertion below is about the record the launcher would read.
 *
 * `native-experience`, *Home-screen quick actions*: the entries survive the app being killed
 * "because the system stores them rather than the app", choosing the library "lands on the
 * shelf", and "every entry is localised in each supported language". *Continuity*: Android
 * "reports the same publication to the launcher as a used shortcut".
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class HomeScreenActionsTest {

    private val context = ApplicationProvider.getApplicationContext<Context>()

    private fun publication(title: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
    )

    /** A publication held on a server, which has no path on this device at all. */
    private fun serverPublication(title: String) = Publication(
        identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(
                sourceId = UUID.fromString("00000000-0000-4000-8000-000000000001"),
                remoteId = "884",
            ),
        ),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
    )

    private fun published(): List<ShortcutInfoCompat> =
        ShortcutManagerCompat.getDynamicShortcuts(context)

    /**
     * The launcher holds the entries the core decided, in the core's order.
     *
     * The rank is asserted because the launcher sorts by it, not by list position: a menu
     * built in the right order and ranked 0, 0, 0 draws in whatever order the system likes.
     */
    @Test
    fun `the launcher holds the core's list, in the core's order and rank`() {
        HomeScreenActions.publish(context, publication("Bone 1"), hasDownloads = true)

        val entries = published().sortedBy { it.rank }
        assertEquals(
            listOf(QuickAction.CONTINUE_ID, QuickAction.LIBRARY_ID, QuickAction.DOWNLOADS_ID),
            entries.map { it.id },
        )
        assertEquals(listOf(0, 1, 2), entries.map { it.rank })
    }

    /**
     * Publishing replaces the menu rather than adding to it.
     *
     * The file's own reasoning: "a menu assembled by mutation is a menu that can hold two
     * continue entries for two different books".
     */
    @Test
    fun `publishing a second time leaves no entry from the first`() {
        HomeScreenActions.publish(context, publication("Bone 1"), hasDownloads = true)
        HomeScreenActions.publish(context, continuing = null, hasDownloads = false)

        assertEquals(listOf(QuickAction.LIBRARY_ID), published().map { it.id })
    }

    /**
     * The continue entry carries the publication's key, not the file it was last seen at.
     *
     * A server publication is used for the second half because it has no path on this
     * device: its key is `srv:…`, so an entry that had smuggled a path in would show it.
     */
    @Test
    fun `the continue entry carries an identifier the library can be asked for`() {
        val bone = publication("Bone 1")
        HomeScreenActions.publish(context, bone, hasDownloads = false)

        val entry = published().first { it.id == QuickAction.CONTINUE_ID }
        assertEquals(bone.id, entry.intent.getStringExtra(HomeScreenActions.EXTRA_PUBLICATION))

        val remote = serverPublication("Saga 3")
        HomeScreenActions.publish(context, remote, hasDownloads = false)
        val remoteEntry = published().first { it.id == QuickAction.CONTINUE_ID }
        val carried = remoteEntry.intent.getStringExtra(HomeScreenActions.EXTRA_PUBLICATION)
        assertEquals(remote.id, carried)
        assertFalse(
            "the continue entry carries a filesystem path, which a menu outlives",
            carried!!.contains('/'),
        )
    }

    /**
     * Every entry the app publishes reads back as the request it stands for.
     *
     * The round trip rather than either half: `publish` and `requestFrom` are the two ends
     * of one contract, and each is capable of passing its own assertions while disagreeing
     * with the other about an extra's name.
     */
    @Test
    fun `a published entry reads back as the request it stands for`() {
        val bone = publication("Bone 1")
        HomeScreenActions.publish(context, bone, hasDownloads = true)

        val requests = published().sortedBy { it.rank }.map { HomeScreenActions.requestFrom(it.intent) }
        assertEquals(
            listOf(
                QuickActionRequest.ContinueReading(bone.id),
                QuickActionRequest.Library,
                QuickActionRequest.Downloads,
            ),
            requests,
        )
    }

    /**
     * The library entry asks for the library, not for wherever the app was last left.
     *
     * The scenario states this as a destination: "choosing the library lands on the shelf
     * rather than on wherever the app was last left". What this file owns is the first half
     * — the request the launcher hands over names the library — and `AppNavigationTest` owns
     * what the shell then does with it.
     */
    @Test
    fun `the library entry asks for the library`() {
        HomeScreenActions.publish(context, publication("Bone 1"), hasDownloads = true)

        val library = published().first { it.id == QuickAction.LIBRARY_ID }
        assertEquals(QuickActionRequest.Library, HomeScreenActions.requestFrom(library.intent))
        assertNull(
            "the library entry names a publication, so it would reopen a book instead",
            library.intent.getStringExtra(HomeScreenActions.EXTRA_PUBLICATION),
        )
    }

    /**
     * An intent that is not a quick action is not read as one.
     *
     * The third case is the one that matters. `MainActivity` receives every intent the
     * system sends it — a file handed over from another app arrives at the same door — so a
     * reader who opens a comic from a file manager must not also be sent somewhere by an
     * extra that happens to be present. The action is what tells the two apart.
     */
    @Test
    fun `an intent the launcher did not send is not a request`() {
        assertNull(HomeScreenActions.requestFrom(null))
        assertNull(HomeScreenActions.requestFrom(Intent(Intent.ACTION_VIEW)))

        val handedOver = Intent(Intent.ACTION_VIEW)
            .putExtra(HomeScreenActions.EXTRA_ACTION, QuickAction.LIBRARY_ID)
        assertNull(
            "an intent from elsewhere carrying the library's identifier is read as a tap",
            HomeScreenActions.requestFrom(handedOver),
        )

        // The action is right and the entry is from a menu this app no longer publishes.
        val stale = Intent(HomeScreenActions.ACTION)
            .putExtra(HomeScreenActions.EXTRA_ACTION, "app.storyarc.quickaction.shelves")
        assertNull(HomeScreenActions.requestFrom(stale))
    }

    /**
     * A tap on an entry returns to the app that is already open.
     *
     * Without these flags a reader who taps a quick action while the app is running gets a
     * second copy of it, and the back gesture then walks out through a library they never
     * opened.
     */
    @Test
    fun `an entry returns to the running app rather than starting a second one`() {
        HomeScreenActions.publish(context, publication("Bone 1"), hasDownloads = true)

        for (entry in published()) {
            val flags = entry.intent.flags
            assertTrue(
                "${entry.id} does not clear the task above it",
                flags and Intent.FLAG_ACTIVITY_CLEAR_TOP != 0,
            )
            assertTrue(
                "${entry.id} starts a second copy of the activity",
                flags and Intent.FLAG_ACTIVITY_SINGLE_TOP != 0,
            )
        }
    }

    /**
     * Opening a publication re-points the menu at it.
     *
     * `Continuity` on Android is the launcher's own record: there is no Handoff and no
     * backend to invent one with, so the mirror is that the launcher is told which book was
     * opened, at the moment it is opened.
     */
    @Test
    fun `opening a publication re-points the menu at it`() {
        val bone = publication("Bone 1")
        HomeScreenActions.publish(context, bone, hasDownloads = false)

        val saga = publication("Saga 3")
        HomeScreenActions.reportOpened(context, saga, hasDownloads = false)

        val entry = published().first { it.id == QuickAction.CONTINUE_ID }
        assertEquals(saga.id, entry.intent.getStringExtra(HomeScreenActions.EXTRA_PUBLICATION))
        assertEquals("the opened publication is not first in the menu", 0, entry.rank)
    }

    /**
     * And it is told through the call that reports the entry as used.
     *
     * This one reads Kotlin source, and it is a tripwire rather than a proof. The
     * difference between `setDynamicShortcuts` and `pushDynamicShortcut` is that the second
     * also reports the shortcut used, which is what lets the launcher rank it and the
     * Assistant answer for it — and a shortcut store cannot be asked afterwards which of
     * the two put an entry there. The test above proves the entry is right; this proves the
     * app used the call that reports it.
     *
     * `app/build.gradle.kts` declares the Kotlin tree as an input of this task, so this
     * fails on an incremental run and not only on a clean one.
     */
    @Test
    fun `the opened publication is reported used and not merely published`() {
        val source = File(androidRoot, "app/src/main/kotlin/app/storyarc/HomeScreenActions.kt")
        assertTrue("HomeScreenActions.kt has moved; this test names it by path", source.isFile)
        val body = source.readText().substringAfter("fun reportOpened(").substringBefore("\n    }")

        assertTrue(
            "reportOpened no longer pushes the entry, so the launcher is never told it was used",
            body.contains("ShortcutManagerCompat.pushDynamicShortcut("),
        )
    }

    /** Every entry is named in every language the app ships. */
    @Test
    @Config(qualifiers = "en-rGB")
    fun `the menu is in English`() = assertMenuReads("Continue reading", "Library", "Downloads")

    @Test
    @Config(qualifiers = "fr-rFR")
    fun `the menu is in French`() =
        assertMenuReads("Reprendre la lecture", "Bibliothèque", "Téléchargements")

    @Test
    @Config(qualifiers = "de-rDE")
    fun `the menu is in German`() = assertMenuReads("Weiterlesen", "Bibliothek", "Downloads")

    @Test
    @Config(qualifiers = "es-rES")
    fun `the menu is in Spanish`() =
        assertMenuReads("Seguir leyendo", "Biblioteca", "Descargas")

    /**
     * The three short labels, in the order the menu holds them.
     *
     * The words are written out rather than looked up through `getString`, because a test
     * that asks the same resource the code asked passes whatever the resource says — an
     * untranslated string included. These are the shipped translations; a locale that loses
     * one falls back to English and fails here by name.
     */
    private fun assertMenuReads(continuing: String, library: String, downloads: String) {
        HomeScreenActions.publish(context, publication("Bone 1"), hasDownloads = true)

        assertEquals(
            listOf(continuing, library, downloads),
            published().sortedBy { it.rank }.map { it.shortLabel.toString() },
        )
    }

    /** And the continue entry says which book, where the launcher has room for it. */
    @Test
    @Config(qualifiers = "fr-rFR")
    fun `the long label names the book`() {
        HomeScreenActions.publish(context, publication("Bone 1"), hasDownloads = false)

        val entry = published().first { it.id == QuickAction.CONTINUE_ID }
        assertEquals("Reprendre Bone 1", entry.longLabel.toString())
    }

    private companion object {
        /**
         * `apps/android`, found rather than hardcoded — the first ancestor holding the
         * settings file. Nothing above `apps/android` has one; the repository's build is
         * pnpm's. Walking up from the working directory is what the other source-reading
         * tests in this module do, and it stays inside the worktree under test.
         */
        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
