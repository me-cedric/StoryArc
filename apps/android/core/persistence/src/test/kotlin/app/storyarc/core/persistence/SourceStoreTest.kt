package app.storyarc.core.persistence

import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The source registry, read back from disk.
 *
 * **This file exists because the round trip was asserted on iOS and by nothing here.**
 * `source-lifecycle` task 6.1 names the gap. iOS's `SourceStoreTests` makes the first seven
 * claims below, in this order; the last two have no iOS counterpart because the code they
 * cover has none — `StoredRegistry.toDomain` drops a kind this build does not know, and
 * `registry()` swallows a decode failure. Both are deliberate, both are stated in
 * `SourceStore`'s own comments, and neither was asserted anywhere.
 */
class SourceStoreTest {

    private fun store() = SourceStore(FakePreferences())

    @Test
    fun `an empty store reports an empty registry rather than failing`() {
        assertTrue(store().registry().sources.isEmpty())
    }

    @Test
    fun `order survives a save and a read, because order carries meaning`() {
        // `sources`: the combined library "lists titles from higher sources first when two
        // sources hold the same publication". A store that returned a set would lose that.
        val store = store()
        store.save(
            SourceRegistry()
                .adding(Source(displayName = "Comics", kind = SourceKind.LOCAL_FOLDER))
                .adding(Source(displayName = "Kavita", kind = SourceKind.KAVITA_SERVER))
                .adding(Source(displayName = "Books", kind = SourceKind.OPDS_CATALOG)),
        )

        assertEquals(
            listOf("Comics", "Kavita", "Books"),
            store.registry().sources.map { it.displayName },
        )
    }

    @Test
    fun `a source keeps its identifier, so its progress and credentials still resolve`() {
        val store = store()
        val only = Source(
            displayName = "Kavita",
            kind = SourceKind.KAVITA_SERVER,
            credentialReference = "ref",
        )
        store.save(SourceRegistry().adding(only))

        val read = store.registry()[only.id]

        assertEquals(only.id, read?.id)
        assertEquals("ref", read?.credentialReference)
        assertEquals(SourceKind.KAVITA_SERVER, read?.kind)
    }

    @Test
    fun `a tombstone survives, or the thirty-day promise would reset on every launch`() {
        val store = store()
        val only = Source(displayName = "Kavita", kind = SourceKind.KAVITA_SERVER)
        store.save(SourceRegistry().adding(only).removing(only.id, atEpochMillis = 500))

        val read = store.registry()

        assertEquals(1, read.tombstones.size)
        assertEquals(only.id, read.tombstones.first().sourceId)
        assertEquals(500L, read.tombstones.first().removedAtEpochMillis)
    }

    @Test
    fun `connection state is not stored, because it describes a network right now`() {
        // A state read back from disk is a claim about the past. Loading as `Connecting` is
        // the honest thing to show on a cold launch, and it is what iOS does too.
        val store = store()
        val only = Source(
            displayName = "Kavita",
            kind = SourceKind.KAVITA_SERVER,
            state = SourceConnectionState.Connected,
        )
        store.save(SourceRegistry().adding(only))

        assertEquals(SourceConnectionState.Connecting, store.registry()[only.id]?.state)
    }

    @Test
    fun `a reset forgets every source`() {
        val store = store()
        store.save(
            SourceRegistry().adding(Source(displayName = "Comics", kind = SourceKind.LOCAL_FOLDER)),
        )
        store.reset()

        assertTrue(store.registry().sources.isEmpty())
    }

    @Test
    fun `a source keeps its locator, which is what a rename must not break`() {
        // The bug this prevents: a folder is matched to its source to decide whether it is
        // already registered. Matching by display name means a renamed source is not
        // recognised on the next launch and the same folder is added a second time. The
        // locator is where the folder *is*, and a rename never moves it.
        val store = store()
        val only = Source(
            displayName = "Comics",
            kind = SourceKind.LOCAL_FOLDER,
            locator = "content://tree/comics",
        )
        store.save(SourceRegistry().adding(only).renaming(only.id, "Graphic novels"))

        val read = store.registry()[only.id]

        assertEquals("Graphic novels", read?.displayName)
        assertEquals("content://tree/comics", read?.locator)
    }

    @Test
    fun `a kind this build does not know is dropped rather than guessed at`() {
        // `StoredRegistry.toDomain` says why: a source written by a newer version has a type
        // this one cannot fetch from, and drawing it as a folder would be worse than not
        // drawing it. Written as raw JSON because no enum case can produce this — a future
        // build is the only thing that can, which is exactly why nothing asserted it.
        val preferences = FakePreferences()
        preferences.edit().putString(
            "registry",
            """
            {"sources":[
              {"id":"11111111-1111-1111-1111-111111111111","displayName":"From the future",
               "kind":"HOLOGRAM"},
              {"id":"22222222-2222-2222-2222-222222222222","displayName":"Comics",
               "kind":"LOCAL_FOLDER"}
            ],"tombstones":[]}
            """.trimIndent(),
        ).apply()

        val read = SourceStore(preferences).registry()

        assertEquals(listOf("Comics"), read.sources.map { it.displayName })
    }

    @Test
    fun `a registry that cannot be decoded reads as empty rather than throwing`() {
        // `registry()` wraps the decode in `runCatching`. A reader whose preferences were
        // truncated gets an empty library and can add a source again; an exception here would
        // be thrown on the launch path, before anything is on screen.
        val preferences = FakePreferences()
        preferences.edit().putString("registry", "{not json").apply()

        val read = SourceStore(preferences).registry()

        assertTrue(read.sources.isEmpty())
        assertTrue(read.tombstones.isEmpty())
        assertNull(read[java.util.UUID.randomUUID()])
    }
}
