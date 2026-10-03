package app.storyarc.core.model

import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The event task 5.12's second clause reports: a reader found its share gone while the
 * network path moved under it, and the library has nothing open to learn that on its own.
 *
 * Each test launches its own collector before reporting, the way the real one does: the
 * library starts watching once, at launch, before anything could be unreachable yet. A
 * `MutableSharedFlow` only delivers to a subscriber already listening, so `yield()` hands the
 * collector coroutine the chance to reach its own `collect` call before either test reports
 * anything.
 */
class SourceReachabilityEventsTest {

    @Test
    fun `a reported source is what a collector receives`() = runBlocking {
        val sourceId = UUID.randomUUID()
        val received = CompletableDeferred<UUID>()
        val job = launch { SourceReachabilityEvents.unreachable.collect { received.complete(it) } }
        yield()

        SourceReachabilityEvents.reportUnreachable(sourceId)

        assertEquals(sourceId, withTimeout(5_000) { received.await() })
        job.cancel()
    }

    @Test
    fun `two reports both reach a collector that is already listening`() = runBlocking {
        val first = UUID.randomUUID()
        val second = UUID.randomUUID()
        val received = mutableListOf<UUID>()
        val both = CompletableDeferred<Unit>()
        val job = launch {
            SourceReachabilityEvents.unreachable.collect {
                received += it
                if (received.size == 2) both.complete(Unit)
            }
        }
        yield()

        SourceReachabilityEvents.reportUnreachable(first)
        SourceReachabilityEvents.reportUnreachable(second)
        withTimeout(5_000) { both.await() }

        assertEquals(listOf(first, second), received)
        job.cancel()
    }
}
