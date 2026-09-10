package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Which sources the shelf says it is still reading.
 *
 * A reader adds a Kavita server, opens the library and sees the shelf they already had.
 * `KavitaClient` waits twenty seconds before giving up, so for twenty seconds the app is
 * indistinguishable from one that ignored the source. The Kavita browser stopped being
 * silent about this in `92deec66`; this is the shelf's half.
 *
 * **The three cases that must not be counted are the point of the test.** A source that
 * answered and holds nothing is not waiting; one that is unreachable is a different
 * sentence, already carried elsewhere; and a local folder is walked by this app, with its
 * own indicator. A notice that is usually wrong is a notice a reader learns to ignore.
 *
 * iOS's `StillBeingReadTests` asserts the same six cases.
 */
class StillBeingReadTest {

    private fun source(
        kind: SourceKind = SourceKind.KAVITA_SERVER,
        state: SourceConnectionState = SourceConnectionState.Connecting,
        id: UUID = UUID.randomUUID(),
    ) = Source(id = id, kind = kind, displayName = "A place", locator = "https://x.invalid", state = state)

    private fun row(sourceId: UUID?) = Publication(
        identity = PublicationIdentity(contentDigest = UUID.randomUUID().toString()),
        format = PublicationFormat.CBZ,
        displayTitle = "Something",
        origin = MetadataOrigin.INFERRED,
        sourceId = sourceId,
    )

    @Test
    fun `a server still being asked, with nothing on the shelf, is being read`() {
        val waiting = source()

        assertEquals(1, sourcesStillBeingRead(listOf(waiting), publications = emptyList()))
    }

    @Test
    fun `a server that has put something on the shelf is not still being read`() {
        val answered = source()

        assertEquals(0, sourcesStillBeingRead(listOf(answered), listOf(row(answered.id))))
    }

    @Test
    fun `a server that answered and holds nothing says nothing`() {
        // The case that would make this notice a liar. A connected server with an empty
        // library is not waiting, and a line that stayed up for ever is one a reader learns
        // to ignore — including on the day it is true.
        val empty = source(state = SourceConnectionState.Connected)

        assertEquals(0, sourcesStillBeingRead(listOf(empty), publications = emptyList()))
    }

    @Test
    fun `an unreachable server is a different sentence, so it is not this one`() {
        val away = source(state = SourceConnectionState.Unreachable(sinceEpochMillis = 0L))

        assertEquals(0, sourcesStillBeingRead(listOf(away), publications = emptyList()))
    }

    @Test
    fun `a local folder is never counted, because the scan says so itself`() {
        val folder = source(kind = SourceKind.LOCAL_FOLDER)

        assertEquals(0, sourcesStillBeingRead(listOf(folder), publications = emptyList()))
    }

    @Test
    fun `two servers waiting are two, and one of them answering leaves one`() {
        val first = source()
        val second = source()

        assertEquals(2, sourcesStillBeingRead(listOf(first, second), publications = emptyList()))
        assertEquals(1, sourcesStillBeingRead(listOf(first, second), listOf(row(first.id))))
    }
}
