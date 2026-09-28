package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID

/**
 * What taking the undo offer gives a reader back.
 *
 * `collections-and-reading-lists`: marking a collection or a list read updates "every member's
 * read state" and "the action is undoable for 10 seconds". The ten seconds are the snackbar's;
 * what comes back when the offer is taken is this.
 *
 * Only what the action changed comes back. That is the whole difficulty: the record holds the
 * change, never the selection, so an undo cannot unread a publication the reader finished last
 * month, and cannot take a publication out of a collection they put there last week. Both of
 * those are silent losses -- nothing draws an error, the reader simply has less than they had.
 *
 * Robolectric, for `ShelfCoverMenuTest`'s reason: [LibraryViewModel] takes an `Application`.
 * No store is passed, so nothing here writes to the machine the test runs on.
 *
 * iOS's `BulkUndoTests` asserts these cases one for one.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
// 34 for the reason `ShelfDeletionDialogTest` gives: Robolectric has no image for 37.
@Config(sdk = [34])
class BulkUndoTest {

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun issue(number: String) = Publication(
        identity = PublicationIdentity(normalizedPath = "/Crossover/$number.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = "Crossover #$number",
        origin = MetadataOrigin.EMBEDDED,
    )

    private fun collection(named: String, model: LibraryViewModel): UUID {
        model.createCollection(named)
        return model.shelves.value.collections.last().id
    }

    // MARK: - Membership

    @Test
    fun `undoing an add takes out what was added and leaves what was already there`() = runTest {
        // The member that was already in the collection is not part of what the action
        // changed, so it must survive the undo. A record built from the selection instead of
        // the change would take it out, and nothing on screen would say so.
        val model = LibraryViewModel(application)
        val id = collection("Image Comics", model)
        model.addToCollection(setOf("a"), id)

        val changed = model.addSelectionToCollection(setOf("a", "b", "c"), id)
        assertEquals(setOf("b", "c"), changed)

        BulkUndo(BulkUndo.Kind.Collection(id), changed)
            .reverse(model, publications = emptyList(), onMark = { _, _ -> }, promoter = null)

        assertEquals(setOf("a"), model.shelves.value.collections.first().members)
    }

    @Test
    fun `undoing an append takes out what was appended and leaves the order of the rest`() =
        runTest {
            val model = LibraryViewModel(application)
            model.createList("Crossover")
            val id = model.shelves.value.lists.first().id
            model.appendToList(listOf("a", "b"), id)

            BulkUndo(BulkUndo.Kind.Listing(id), setOf("b"))
                .reverse(model, publications = emptyList(), onMark = { _, _ -> }, promoter = null)

            assertEquals(listOf("a"), model.shelves.value.lists.first().entries)
        }

    @Test
    fun `an undo reaches the shelf it names and no other`() = runTest {
        val model = LibraryViewModel(application)
        val first = collection("Image Comics", model)
        val second = collection("To read with my kid", model)
        model.addToCollection(setOf("a"), first)
        model.addToCollection(setOf("a"), second)

        BulkUndo(BulkUndo.Kind.Collection(first), setOf("a"))
            .reverse(model, publications = emptyList(), onMark = { _, _ -> }, promoter = null)

        val shelves = model.shelves.value.collections
        assertTrue(shelves.first { it.id == first }.members.isEmpty())
        assertEquals(setOf("a"), shelves.first { it.id == second }.members)
    }

    // MARK: - Read state

    @Test
    fun `undoing a mark read unreads exactly what the mark changed`() = runTest {
        // The screen owns the marking itself, so what this asserts is which publications the
        // undo asks for and in which direction. Asking for the whole selection would unread an
        // entry the reader finished before the action ran.
        val model = LibraryViewModel(application)
        val entries = listOf(issue("1"), issue("2"), issue("3"))
        val changed = setOf(entries[1].id, entries[2].id)
        val marked = mutableListOf<Pair<String, Boolean>>()

        BulkUndo(BulkUndo.Kind.Read(wasRead = true), changed)
            .reverse(
                viewModel = model,
                publications = entries,
                onMark = { publication, read -> marked += publication.id to read },
                promoter = null,
            )

        assertEquals(changed, marked.map { it.first }.toSet())
        assertTrue(marked.all { !it.second })
    }

    @Test
    fun `undoing a copy onto a server takes the list back off that server`() = runTest {
        val model = LibraryViewModel(application)
        val source = UUID.randomUUID().toString()
        var withdrawn: Pair<String, Int>? = null
        val promoter = ListPromoter(
            plan = { _, _ -> error("the plan is not asked for by an undo") },
            copy = { _, _ -> error("the copy is not run again by an undo") },
            withdraw = { sourceId, listId -> withdrawn = sourceId to listId },
        )

        BulkUndo(BulkUndo.Kind.Promoted(source, 7), setOf("a"))
            .reverse(model, publications = emptyList(), onMark = { _, _ -> }, promoter = promoter)

        assertEquals(source to 7, withdrawn)
    }
}
