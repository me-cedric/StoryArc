package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The record the home-screen widget reads, asserted against the same table as iOS's
 * `ReadingSnapshotTests`. Add a case here, add it there.
 */
class ReadingSnapshotTest {

    private fun publication(title: String, series: String? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "/library/$title"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        series = series,
        origin = MetadataOrigin.INFERRED,
    )

    @Test
    fun `no publication, or one with a blank title, gives no snapshot`() {
        assertNull(ReadingSnapshot.of(null, 0.5))
        assertNull(ReadingSnapshot.of(publication("   "), 0.5))
    }

    @Test
    fun `the percent is rounded down, so only a finished book shows 100`() {
        val bone = publication("Bone 1")
        assertEquals(99, ReadingSnapshot.of(bone, 0.996)?.percentRead)
        assertEquals(100, ReadingSnapshot.of(bone, 1.0)?.percentRead)
        assertNull(ReadingSnapshot.of(bone, null)?.percentRead)
        assertEquals(0, ReadingSnapshot.of(bone, -0.2)?.percentRead)
        assertEquals(29, ReadingSnapshot.of(bone, 0.29)?.percentRead)
        assertEquals(42, ReadingSnapshot.of(bone, 0.42f.toDouble())?.percentRead)
    }

    @Test
    fun `a snapshot survives its stored form`() {
        val snapshot = ReadingSnapshot.of(publication("Bone 1", series = "Bone"), 0.42)!!
        assertEquals(snapshot, ReadingSnapshot.decoded(snapshot.encoded()))
        assertEquals("Bone", snapshot.series)
        assertEquals(0.42f, snapshot.fractionRead)
    }

    @Test
    fun `a record in another format, malformed, or with no title is not read`() {
        assertNull(ReadingSnapshot.decoded("""{"version":2,"publicationID":"a","title":"Bone 1"}"""))
        assertNull(ReadingSnapshot.decoded("""{"version":1,"publicationID":"a","title":"  "}"""))
        assertNull(ReadingSnapshot.decoded("""{"version":1,"publicationID":"","title":"Bone 1"}"""))
        assertNull(ReadingSnapshot.decoded("not json"))
        assertEquals(
            100,
            ReadingSnapshot.decoded("""{"version":1,"publicationID":"a","title":"Bone 1","percentRead":140}""")
                ?.percentRead,
        )
    }

    /** Shared with iOS's `ReadingSnapshotTests`: the same identifier names the same file. */
    @Test
    fun `the cover file name is the FNV-1a hash of the identifier`() {
        assertEquals("cover-8082a1c0582fd210.jpg", ReadingSnapshot.coverFile("path:/library/Bone 1"))
        assertEquals("cover-cbf29ce484222325.jpg", ReadingSnapshot.coverFile(""))
    }
}
