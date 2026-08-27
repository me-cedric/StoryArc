package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.UUID

/**
 * The source registry: order, renaming, removal, and the thirty days that follow it.
 *
 * The retention half carries the risk. `sources` requires reading progress to outlive a
 * removed source by 30 days, and losing a reading position is the one thing ADR-0006 says
 * the app must never do. So the clock is a parameter here rather than `System
 * .currentTimeMillis()` — a test that waits thirty days is a test nobody runs. iOS's
 * `SourceRegistryTests` asserts the same table.
 */
class SourceRegistryTest {

    private fun source(name: String, kind: SourceKind = SourceKind.LOCAL_FOLDER) =
        Source(displayName = name, kind = kind)

    @Test
    fun `a new source goes to the end because the order is the reader's`() {
        val registry = SourceRegistry().adding(source("Comics")).adding(source("Books"))

        assertEquals(listOf("Comics", "Books"), registry.sources.map { it.displayName })
    }

    @Test
    fun `adding the same source twice does not list it twice`() {
        val only = source("Comics")

        assertEquals(1, SourceRegistry().adding(only).adding(only).sources.size)
    }

    @Test
    fun `a drag downwards lands where the drag reported, not one place early`() {
        // The destination a drag reports is an index in the list *before* the move.
        // Removing first and inserting at that index lands one place early every time.
        val a = source("A")
        val registry = SourceRegistry().adding(a).adding(source("B")).adding(source("C"))

        assertEquals(
            listOf("B", "A", "C"),
            registry.moving(a.id, 2).sources.map { it.displayName },
        )
    }

    @Test
    fun `a drag upwards lands where the drag reported`() {
        val c = source("C")
        val registry = SourceRegistry().adding(source("A")).adding(source("B")).adding(c)

        assertEquals(
            listOf("C", "A", "B"),
            registry.moving(c.id, 0).sources.map { it.displayName },
        )
    }

    @Test
    fun `a destination past the end clamps rather than throwing`() {
        val a = source("A")
        val registry = SourceRegistry().adding(a).adding(source("B"))

        assertEquals(listOf("B", "A"), registry.moving(a.id, 99).sources.map { it.displayName })
    }

    @Test
    fun `renaming keeps the source's identity so everything referring to it follows`() {
        val only = source("Comcis")
        val registry = SourceRegistry().adding(only).renaming(only.id, "Comics")

        assertEquals("Comics", registry[only.id]?.displayName)
        assertEquals(only.id, registry[only.id]?.id)
    }

    @Test
    fun `a blank name is refused because the name appears inside sentences`() {
        val only = source("Comics")
        val registry = SourceRegistry().adding(only)

        assertEquals(registry.sources, registry.renaming(only.id, "   ").sources)
    }

    @Test
    fun `a name is stored trimmed`() {
        val only = source("x")
        val registry = SourceRegistry().adding(only).renaming(only.id, "  Comics\n")

        assertEquals("Comics", registry[only.id]?.displayName)
    }

    @Test
    fun `removal takes the source out and leaves a tombstone behind`() {
        val only = source("Kavita", SourceKind.KAVITA_SERVER)
        val registry = SourceRegistry().adding(only).removing(only.id, 1_000_000)

        assertTrue(registry.sources.isEmpty())
        assertEquals(listOf(only.id), registry.tombstones.map { it.sourceId })
    }

    @Test
    fun `progress is not collectable the day before the thirty are up`() {
        val only = source("Kavita")
        val registry = SourceRegistry().adding(only).removing(only.id, 0)

        val (after, expired) = registry.collectingExpiredTombstones(
            SourceTombstone.RETENTION_MILLIS - 1,
        )

        assertTrue(expired.isEmpty())
        assertEquals(1, after.tombstones.size)
    }

    @Test
    fun `progress is collectable once the thirty days are up`() {
        val only = source("Kavita")
        val registry = SourceRegistry().adding(only).removing(only.id, 0)

        val (after, expired) = registry.collectingExpiredTombstones(SourceTombstone.RETENTION_MILLIS)

        assertEquals(listOf(only.id), expired)
        assertTrue(after.tombstones.isEmpty())
    }

    @Test
    fun `re-adding a source inside the thirty days keeps its progress`() {
        // The promise `sources` makes: "re-adding the same source restores where the user
        // stopped". It is only true if the tombstone goes, otherwise the collection pass
        // deletes the progress of a source the reader is using again.
        val only = source("Kavita")
        val registry = SourceRegistry().adding(only).removing(only.id, 0).readding(only)

        val (_, expired) = registry.collectingExpiredTombstones(
            SourceTombstone.RETENTION_MILLIS * 2,
        )

        assertTrue(registry.tombstones.isEmpty())
        assertTrue(expired.isEmpty())
        assertNotNull(registry[only.id])
    }

    @Test
    fun `collecting one expired tombstone leaves a younger one alone`() {
        val old = source("Old")
        val recent = source("Recent")
        val registry = SourceRegistry()
            .adding(old)
            .adding(recent)
            .removing(old.id, 0)
            .removing(recent.id, SourceTombstone.RETENTION_MILLIS)

        val (after, expired) = registry.collectingExpiredTombstones(
            SourceTombstone.RETENTION_MILLIS + 1,
        )

        assertEquals(listOf(old.id), expired)
        assertEquals(listOf(recent.id), after.tombstones.map { it.sourceId })
    }

    @Test
    fun `removing a source that is not there changes nothing`() {
        val registry = SourceRegistry().adding(source("Comics"))

        assertEquals(registry, registry.removing(UUID.randomUUID(), 1))
    }

    @Test
    fun `an empty registry knows nothing`() {
        assertNull(SourceRegistry()[UUID.randomUUID()])
    }
}
