package app.storyarc.feature.library

import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which sentence a reader gets when the shelf is bare and sources are configured.
 *
 * The branch is the whole substance of `LibraryAway`: *none of the places you added can be
 * reached* and *nothing has arrived from them yet* are two different claims, one about the
 * network and one about the books, and showing the wrong one tells a reader something untrue
 * about their own device. A screenshot proves the layout; only this proves the choice.
 *
 * It also pins the reason the predicate is not simply "no publications": a local folder is
 * marked connected when it is added, so a reader whose only source is an empty folder is not
 * offline — they have an empty folder.
 *
 * iOS asserts the same rule in `LibraryAwayTests`, case for case.
 */
class LibraryAwayTest {

    private fun source(
        name: String,
        kind: SourceKind = SourceKind.OPDS_CATALOG,
        state: SourceConnectionState,
    ) = Source(displayName = name, kind = kind, state = state)

    @Test
    fun aRegistryWithNoSourcesIsNotAwayButUnconfigured() {
        // The first-run state, which is a different screen entirely: `sources` wants one
        // sentence and an offer to open a comic there, not a network complaint.
        assertFalse(everythingAway(SourceRegistry()))
    }

    @Test
    fun everySourceUnreachableIsAway() {
        val registry = SourceRegistry(
            sources = listOf(
                source("Home NAS", SourceKind.NETWORK_SHARE, SourceConnectionState.Unreachable(0L)),
                source("Standard Ebooks", state = SourceConnectionState.Unreachable(0L)),
            ),
        )
        assertTrue(everythingAway(registry))
    }

    @Test
    fun oneSourceStillAnsweringIsNotAway() {
        val registry = SourceRegistry(
            sources = listOf(
                source("Home NAS", SourceKind.NETWORK_SHARE, SourceConnectionState.Unreachable(0L)),
                source("Standard Ebooks", state = SourceConnectionState.Connected),
            ),
        )
        // The reachable one has simply sent nothing yet. Telling this reader that nothing can
        // be reached would be a lie about their network.
        assertFalse(everythingAway(registry))
    }

    @Test
    fun anEmptyLocalFolderIsNotTheNetworkBeingAway() {
        val registry = SourceRegistry(
            sources = listOf(
                source("Comics", SourceKind.LOCAL_FOLDER, SourceConnectionState.Connected),
            ),
        )
        assertFalse(everythingAway(registry))
    }

    @Test
    fun aSourceStillConnectingCountsAsAway() {
        // Connecting is not an error and is not drawn as one — but it cannot fetch, and the
        // honest offer while it cannot is the same one: ask again, or open a comic.
        val registry = SourceRegistry(
            sources = listOf(source("Kavita", state = SourceConnectionState.Connecting)),
        )
        assertTrue(everythingAway(registry))
    }

    @Test
    fun anUnauthorizedSourceIsAwayAsWellAsNeedingAction() {
        val registry = SourceRegistry(
            sources = listOf(
                source("Kavita", state = SourceConnectionState.Unauthorized("401")),
            ),
        )
        assertTrue(everythingAway(registry))
    }
}
