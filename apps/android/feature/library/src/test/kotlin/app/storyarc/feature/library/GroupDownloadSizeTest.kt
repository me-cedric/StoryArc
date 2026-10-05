package app.storyarc.feature.library

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * What a group download states before it starts -- `offline-downloads` 6.4.
 *
 * *Downloading a collection or reading list* requires the app to state "the item count and
 * total size". The size was measured from files on disk, and a member this device has never
 * fetched has no file: ten catalogue rows were confirmed as weighing nothing and then fetched
 * hundreds of megabytes. The feed states a length for each of them, and that is now what is
 * counted.
 *
 * The third case is the other half of 6.4: a group queued OPDS members and silently dropped
 * Kavita chapters, because a chapter's remote identifier carries nothing an OPDS feed can
 * match. iOS asserts the sizes in `GroupDownloadSizeTests.swift`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class GroupDownloadSizeTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private val source = UUID.randomUUID()

    private fun entry(length: Long?) = OpdsEntry(
        id = "hl09",
        title = "Harbour Lights 09",
        acquisitions = listOf(
            OpdsAcquisition(
                href = "https://example.invalid/hl09.epub",
                mediaType = "application/epub+zip",
                kind = OpdsAcquisition.Kind.OPEN,
                length = length,
            ),
        ),
    )

    @Test
    fun `a catalogue row carries the size the feed stated`() {
        val row = OpdsContributor.publication(source, entry(length = 8_400_000L))

        assertEquals(8_400_000L, row?.fileSize)
    }

    @Test
    fun `a catalogue row that states no length is unknown rather than zero`() {
        assertEquals(null, OpdsContributor.publication(source, entry(length = null))?.fileSize)
    }

    @Test
    fun `a member with no file on the device weighs what the server stated`() {
        val row = OpdsContributor.publication(source, entry(length = 8_400_000L))!!

        // No location for it: this device has never fetched from that catalogue.
        val stated = KeepOffline.bytesOnDisk(context.contentResolver, listOf(row)) { null }

        assertEquals(8_400_000L, stated)
    }

    @Test
    fun `a Kavita chapter takes the chapter route and a catalogue entry does not`() {
        assertTrue(KeepOffline.isKavitaChapter(row(remoteId = "chapter:3103")))
        assertFalse(KeepOffline.isKavitaChapter(row(remoteId = "opds:hl09")))
    }

    private fun row(remoteId: String) = Publication(
        identity = PublicationIdentity(
            serverIdentifier = PublicationIdentity.ServerIdentifier(sourceId = source, remoteId = remoteId),
        ),
        format = PublicationFormat.CBZ,
        displayTitle = "Harbour Lights 09",
        origin = MetadataOrigin.AUTHORITATIVE,
    )
}
