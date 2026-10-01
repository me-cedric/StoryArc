package app.storyarc.feature.library

import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.persistence.ImportedCopies
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 10.1: a folder source the system no longer grants is marked `Unreachable` and named,
 * whether or not its tree still appears among the persisted grants.
 */
class FolderAvailabilityTest {

    private fun folder(locator: String, state: SourceConnectionState = SourceConnectionState.Connecting) =
        Source(displayName = locator.substringAfterLast('/'), kind = SourceKind.LOCAL_FOLDER, locator = locator)
            .copy(state = state)

    @Test
    fun `a folder whose tree is still reachable is left alone`() {
        val source = folder("content://tree/Comics")
        val registry = SourceRegistry(sources = listOf(source))

        val result = FolderAvailability.of(registry, reachableLocators = setOf(source.locator!!), atEpochMillis = 100)

        assertTrue(result.newlyUnreachable.isEmpty())
        assertEquals(SourceConnectionState.Connecting, result.registry[source.id]?.state)
    }

    @Test
    fun `a folder whose grant is gone is marked unreachable and named`() {
        val source = folder("content://tree/Manga")
        val registry = SourceRegistry(sources = listOf(source))

        val result = FolderAvailability.of(registry, reachableLocators = emptySet(), atEpochMillis = 500)

        assertEquals(listOf(source), result.newlyUnreachable)
        assertEquals(SourceConnectionState.Unreachable(500), result.registry[source.id]?.state)
    }

    @Test
    fun `a revoked grant that no longer appears among persisted trees at all is still named`() {
        // The caller passes only the trees it could still resolve a display name for, so a
        // fully-revoked grant is simply absent from `reachableLocators` -- never a locator
        // that needs its own special case here.
        val source = folder("content://tree/Gone")
        val registry = SourceRegistry(sources = listOf(source))

        val result = FolderAvailability.of(registry, reachableLocators = setOf("content://tree/Other"), atEpochMillis = 1)

        assertEquals(1, result.newlyUnreachable.size)
        assertEquals("Gone", result.newlyUnreachable.single().displayName)
    }

    @Test
    fun `a folder marked unreachable whose tree answers again is connected again`() {
        val source = folder("content://tree/Card", SourceConnectionState.Unreachable(10))
        val registry = SourceRegistry(sources = listOf(source))

        val result = FolderAvailability.of(registry, reachableLocators = setOf(source.locator!!), atEpochMillis = 20)

        assertTrue(result.newlyUnreachable.isEmpty())
        assertEquals(SourceConnectionState.Connected, result.registry[source.id]?.state)
    }

    @Test
    fun `a non-folder source is never touched`() {
        val server = Source(displayName = "Kavita", kind = SourceKind.KAVITA_SERVER, locator = "https://kavita.example")
        val registry = SourceRegistry(sources = listOf(server))

        val result = FolderAvailability.of(registry, reachableLocators = emptySet(), atEpochMillis = 1)

        assertTrue(result.newlyUnreachable.isEmpty())
        assertEquals(server, result.registry[server.id])
    }

    @Test
    fun `the imported copies' own source is not a picked folder, and is left alone`() {
        val imported = Source(
            id = ImportedCopies.SOURCE_ID,
            displayName = "On this device",
            kind = SourceKind.LOCAL_FOLDER,
            locator = "storyarc/imported",
        ).copy(state = SourceConnectionState.Connected)
        val registry = SourceRegistry(sources = listOf(imported))

        val result = FolderAvailability.of(registry, reachableLocators = emptySet(), atEpochMillis = 1)

        assertTrue(result.newlyUnreachable.isEmpty())
        assertEquals(imported, result.registry[imported.id])
    }

    @Test
    fun `no folder sources at all returns the same registry instance`() {
        val registry = SourceRegistry()

        val result = FolderAvailability.of(registry, reachableLocators = emptySet(), atEpochMillis = 1)

        assertSame(registry, result.registry)
    }
}
