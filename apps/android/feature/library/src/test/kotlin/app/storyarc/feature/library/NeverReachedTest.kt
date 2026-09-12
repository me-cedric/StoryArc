package app.storyarc.feature.library

import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Which sources the library says it has never read.
 *
 * `library-browsing`'s *A source that has never been reached*: the library "says that source
 * has not been read yet, names it, and offers to try again". The name is the part nothing
 * carried before — [sourcesStillBeingRead] returns a count, [LibraryNotice.of] returns
 * [LibraryNotice.Nothing], and [LibraryAway] draws a sentence that names nobody.
 *
 * **The four cases that must not be named are the point of the test.** A source that
 * answered once is away rather than unread; a source still being asked is the
 * still-being-read sentence; a source that needs a sign-in needs an action *Try again*
 * cannot supply; and a local folder is connected the moment it is added.
 *
 * iOS's `NeverReachedTests` asserts the same six cases.
 */
class NeverReachedTest {

    private fun source(
        kind: SourceKind = SourceKind.KAVITA_SERVER,
        state: SourceConnectionState = SourceConnectionState.Unreachable(sinceEpochMillis = 0L),
        answeredAt: Long? = null,
        name: String = "Attic NAS",
    ) = Source(
        displayName = name,
        kind = kind,
        state = state,
        lastSuccessfulSyncEpochMillis = answeredAt,
        locator = "https://x.invalid",
    )

    @Test
    fun `a server that was asked and never answered is named`() {
        assertEquals(listOf("Attic NAS"), sourcesNeverReached(listOf(source())))
    }

    @Test
    fun `a server that answered before is away rather than unread, so it is not named`() {
        // The stamp is the record. `SourceRegistry.marking` writes it on every Connected
        // answer and keeps it through a later refusal, so a source with a stamp has been
        // read once — telling that reader it "has not been read yet" would be false.
        assertEquals(emptyList<String>(), sourcesNeverReached(listOf(source(answeredAt = 1_000L))))
    }

    @Test
    fun `a server still being asked is not named, because that is the other sentence`() {
        // `sourcesStillBeingRead` carries this one. It also makes the retry legible: a probe
        // marks the source Connecting, this list empties, and the still-being-read line takes
        // over until the probe lands.
        val asking = source(state = SourceConnectionState.Connecting)

        assertEquals(emptyList<String>(), sourcesNeverReached(listOf(asking)))
    }

    @Test
    fun `a server that needs a sign-in is not named, because trying again cannot answer it`() {
        val refused = source(state = SourceConnectionState.Unauthorized(reason = "Sign-in needed"))

        assertEquals(emptyList<String>(), sourcesNeverReached(listOf(refused)))
    }

    @Test
    fun `a local folder is never named, because it is connected the moment it is added`() {
        val folder = source(kind = SourceKind.LOCAL_FOLDER)

        assertEquals(emptyList<String>(), sourcesNeverReached(listOf(folder)))
    }

    @Test
    fun `two unread servers are both named, in the order they were added`() {
        val first = source(name = "Attic NAS")
        val second = source(name = "StoryArc Test Catalogue")

        assertEquals(
            listOf("Attic NAS", "StoryArc Test Catalogue"),
            sourcesNeverReached(listOf(first, second)),
        )
    }
}
