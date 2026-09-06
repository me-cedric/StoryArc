package app.storyarc.feature.library

import app.storyarc.core.model.LibraryScope
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.UUID

/**
 * What one pull re-fetches, and what it leaves alone.
 *
 * `sources`' *Refreshing a source*: "when a reader pulls to refresh … the app re-fetches the
 * catalogue in the background". This pull called `rescan()` and nothing else, so a reader who
 * pulled on a shelf showing a server got a folder walk and no catalogue fetch at all. iOS
 * asked every server *and* walked every folder on every pull, whatever the shelf was showing,
 * which is the other way to be wrong: a reader on a metered link paid for the whole library
 * because they pulled one shelf.
 *
 * Both now refresh the sources the shelf is showing. A folder walk is local disk and costs no
 * data, so it runs whenever the shelf could hold a folder's publications; the network is asked
 * only when the shelf is showing something that is reached over one.
 *
 * iOS's `ShelfRefreshTests` holds this table case for case.
 */
class ShelfRefreshTest {

    private fun source(kind: SourceKind) = Source(
        displayName = "Fixture",
        kind = kind,
        state = SourceConnectionState.Connected,
    )

    private fun registry(vararg kinds: SourceKind) =
        kinds.fold(SourceRegistry()) { registry, kind -> registry.adding(source(kind)) }

    @Test
    fun `the whole shelf walks the folders, because that costs no data`() {
        assertTrue(ShelfRefresh.of(LibraryScope.AllSources, registry(SourceKind.KAVITA_SERVER)).walksFolders)
    }

    @Test
    fun `the whole shelf asks the network when something on it is reached over one`() {
        for (kind in listOf(SourceKind.KAVITA_SERVER, SourceKind.OPDS_CATALOG, SourceKind.NETWORK_SHARE)) {
            val plan = ShelfRefresh.of(LibraryScope.AllSources, registry(SourceKind.LOCAL_FOLDER, kind))
            assertTrue("a shelf holding a $kind asked nothing", plan.asksNetwork)
        }
    }

    @Test
    fun `a library of folders alone asks no network, however often it is pulled`() {
        assertFalse(ShelfRefresh.of(LibraryScope.AllSources, registry(SourceKind.LOCAL_FOLDER)).asksNetwork)
        assertFalse(ShelfRefresh.of(LibraryScope.AllSources, registry()).asksNetwork)
    }

    @Test
    fun `a shelf narrowed to one server asks that server and skips the folder walk`() {
        for (kind in listOf(SourceKind.KAVITA_SERVER, SourceKind.OPDS_CATALOG, SourceKind.NETWORK_SHARE)) {
            val server = source(kind)
            val registry = SourceRegistry().adding(server).adding(source(SourceKind.LOCAL_FOLDER))
            val plan = ShelfRefresh.of(LibraryScope.OneSource(server.id), registry)
            assertTrue("a shelf showing a $kind asked it nothing", plan.asksNetwork)
            assertFalse("a reader on a metered link paid for a folder walk too", plan.walksFolders)
        }
    }

    @Test
    fun `a shelf narrowed to one folder walks the folders and asks no network`() {
        val folder = source(SourceKind.LOCAL_FOLDER)
        val registry = SourceRegistry().adding(folder).adding(source(SourceKind.KAVITA_SERVER))
        val plan = ShelfRefresh.of(LibraryScope.OneSource(folder.id), registry)
        assertTrue(plan.walksFolders)
        assertFalse("a folder is on this device, so nothing has to be asked", plan.asksNetwork)
    }

    @Test
    fun `a scope naming a source that has gone is the whole shelf again`() {
        // `LibraryScope.resolved` already answers this for the view; the plan asks it too, so
        // a scope restored at launch that points at a removed source refreshes the library
        // rather than nothing at all.
        val registry = registry(SourceKind.LOCAL_FOLDER, SourceKind.KAVITA_SERVER)
        assertEquals(
            ShelfRefresh.of(LibraryScope.AllSources, registry),
            ShelfRefresh.of(LibraryScope.OneSource(UUID.randomUUID()), registry),
        )
    }

    /**
     * That the pull consults the plan, which is the half a pure decision cannot prove.
     *
     * A rule asserted and never called is indistinguishable from a rule that works —
     * AGENTS.md section 5 catalogues three of them in this repository. The honest test drags a
     * real shelf down on a device; that needs one, so this reads the source instead and says
     * only what source text may honestly say: that the calls exist, and that both refreshes
     * sit after the plan. `SourceRetryWiringTest` makes the same second choice for the same
     * reason.
     */
    @Test
    fun `the pull consults the plan before it refreshes anything`() {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:library:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, SCREEN_SOURCE)
        assertTrue("$SCREEN_SOURCE is not under ${module.absolutePath} — has it moved?", file.isFile)

        val screen = file.readText()
        val pull = screen.indexOf("PullToRefreshBox(")
        assertTrue("LibraryScreen no longer draws a pull to refresh.", pull >= 0)
        val body = screen.substring(pull)
        val plan = body.indexOf("ShelfRefresh.of(")
        val walk = body.indexOf("rescan()")
        val ask = body.indexOf("onProbeSources()")

        assertTrue(
            "The pull refreshes without asking what the shelf is showing.",
            plan in 0 until minOf(walk, ask),
        )
        assertTrue(
            "The pull no longer re-fetches a server. That was the defect: a reader who" +
                " pulled on a populated shelf got a folder walk and no catalogue fetch.",
            ask >= 0,
        )
        assertTrue("The pull no longer walks a folder.", walk >= 0)
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val SCREEN_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/LibraryScreen.kt"
    }
}
