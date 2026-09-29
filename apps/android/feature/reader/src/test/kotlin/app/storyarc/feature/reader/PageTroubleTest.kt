package app.storyarc.feature.reader

import app.storyarc.core.format.FileSource
import app.storyarc.core.format.PublicationAccess
import app.storyarc.core.format.RandomAccessSource
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.io.File
import java.io.IOException
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * Whether a read may go ahead, decided by the test.
 *
 * [Mode.HOLD] keeps each read waiting until the test lets it through, one at a time or all at
 * once. That is the only way to put the reader in the state `network-share`'s notice is
 * about: a page on screen whose bytes have not arrived yet.
 */
private class Gate {
    enum class Mode { PASS, FAIL, HOLD }

    private var mode = Mode.PASS
    private val held = ArrayDeque<CompletableDeferred<Boolean>>()

    val heldCount: Int get() = synchronized(this) { held.size }

    fun set(next: Mode) {
        val waiting = synchronized(this) {
            mode = next
            if (next == Mode.HOLD) return
            held.toList().also { held.clear() }
        }
        waiting.forEach { it.complete(next == Mode.PASS) }
    }

    fun releaseOne() {
        synchronized(this) { held.removeFirstOrNull() }?.complete(true)
    }

    suspend fun enter(): Boolean {
        val waiting = synchronized(this) {
            when (mode) {
                Mode.PASS -> return true
                Mode.FAIL -> return false
                Mode.HOLD -> CompletableDeferred<Boolean>().also(held::add)
            }
        }
        return waiting.await()
    }
}

/** A fixture archive served over the `smb` scheme, through a [Gate]. */
private class GatedSource(private val file: RandomAccessSource, private val gate: Gate) :
    RandomAccessSource {
    override val length: Long get() = file.length

    override suspend fun read(offset: Long, count: Int): ByteArray {
        if (!gate.enter()) throw IOException("the share is away")
        return file.read(offset, count)
    }
}

/**
 * `network-share`'s *Connection drops while reading*, driven through the reader itself.
 *
 * The notice counts from [ReaderViewModel.pageBlockedSince]: from when the page on screen
 * began to wait, and only for that page. The model here reads a real fixture archive over the
 * `smb` scheme, through a gate that holds or fails each read on cue, so every claim is made
 * through `warm`, `decode` and [recoverCurrentPage] rather than by setting the two times by
 * hand. iOS's `PageTroubleTests` makes the same claims.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PageTroubleTest {

    @Before
    fun registerTheShare() {
        PublicationAccess.register("smb") { path ->
            val host = path.removePrefix("smb://").substringBefore('/')
            GatedSource(FileSource(fixture()), gates.getValue(host))
        }
    }

    private fun fixture(): File {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error("$MODULE_DIRECTORY is unset. Run this test through Gradle.")
        val file = File(module, FIXTURE).canonicalFile
        if (!file.isFile) error("$FIXTURE is not under ${module.absolutePath} — has it moved?")
        return file
    }

    private suspend fun openedOverAShare(): Pair<ReaderViewModel, Gate> {
        val gate = Gate()
        val host = "gate-${UUID.randomUUID()}"
        gates[host] = gate
        val path = "smb://$host/Comics/natural-sort.cbz"
        val model = ReaderViewModel(
            publication = Publication(
                identity = PublicationIdentity(normalizedPath = path),
                format = PublicationFormat.CBZ,
                displayTitle = "Natural Sort",
                origin = MetadataOrigin.INFERRED,
            ),
            resolver = RuntimeEnvironment.getApplication().contentResolver,
            path = path,
        )
        model.open(256)
        assertEquals("the fixture did not open over the gated share", 12, model.pages.value.size)
        model.warm(0)
        assertNull(model.pageBlockedSince)
        return model to gate
    }

    /** Polls, because every read here finishes on a thread of its own. */
    private suspend fun until(condition: () -> Boolean) {
        repeat(400) {
            if (condition()) return
            delay(5)
        }
        fail("the condition never held")
    }

    @Test
    fun `the page on screen counts from when its read began, while the read is open`() = runBlocking {
        val (model, gate) = openedOverAShare()
        gate.set(Gate.Mode.HOLD)
        val before = System.currentTimeMillis()

        val turn = launch { model.warm(5) }
        until { model.pageBlockedSince != null }
        assertTrue(model.pageBlockedSince!! >= before)

        gate.set(Gate.Mode.PASS)
        turn.join()
        assertNotNull(model.decoded[5])
        assertNull(model.pageBlockedSince)
    }

    @Test
    fun `a page turned to while its prefetch is still reading counts from the turn`() = runBlocking {
        val (model, gate) = openedOverAShare()
        gate.set(Gate.Mode.HOLD)
        val first = launch { model.warm(5) }

        // Page 5 through, one read at a time, until it lands. The read that holds after it is
        // a neighbour's prefetch.
        until { gate.heldCount > 0 }
        while (model.decoded[5] == null) {
            gate.releaseOne()
            until { model.decoded[5] != null || gate.heldCount > 0 }
        }
        until { gate.heldCount > 0 }
        val neighbour = model.reading.first { it != 5 }
        assertNull("a neighbour's prefetch was counted as the page on screen's", model.pageBlockedSince)

        val second = launch { model.warm(neighbour) }
        until { model.currentIndex == neighbour }
        assertNotNull("the page turned to waits on a read already under way", model.pageBlockedSince)

        gate.set(Gate.Mode.PASS)
        first.join()
        second.join()
        assertNotNull(model.decoded[neighbour])
        assertNull(model.pageBlockedSince)
    }

    @Test
    fun `a failed read, and a retry that fails again, keep the time the page began to wait`() = runBlocking {
        val (model, gate) = openedOverAShare()
        gate.set(Gate.Mode.HOLD)
        val turn = launch { model.warm(5) }
        until { model.pageBlockedSince != null }
        val began = model.pageBlockedSince
        // A clock that moves between the wait and the failure, so the two cannot agree by luck.
        delay(20)

        gate.set(Gate.Mode.FAIL)
        turn.join()
        assertNull(model.decoded[5])
        assertEquals("the notice restarted when the read gave up", began, model.pageBlockedSince)

        delay(20)
        model.recoverCurrentPage()
        assertEquals("a retry restarted the notice", began, model.pageBlockedSince)
    }

    @Test
    fun `the page on screen is read again once the share answers, without a turn`() = runBlocking {
        val (model, gate) = openedOverAShare()
        gate.set(Gate.Mode.FAIL)
        model.warm(5)
        assertNull(model.decoded[5])
        assertNotNull(model.pageBlockedSince)

        gate.set(Gate.Mode.PASS)
        model.recoverCurrentPage()
        assertNotNull(model.decoded[5])
        assertNull(model.pageBlockedSince)
        // Marked as read, as `warm` marks one: otherwise the next warm reads it a second time,
        // and a page the decoder refused would spin for ever instead of naming its codec.
        assertTrue(5 in model.attempted)
    }

    private companion object {
        val gates = ConcurrentHashMap<String, Gate>()

        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
        const val FIXTURE = "../../../../packages/test-fixtures/comics/natural-sort.cbz"
    }
}
