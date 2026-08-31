package app.storyarc.feature.library

import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.model.StreamingCapability
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.util.UUID

/**
 * What a cover is allowed to say, decided without a device.
 *
 * `library-browsing` caps a cover at two marks and forbids a third, and both of the rules
 * asserted here answer the second of the two — whether the publication can be read with no
 * network. One draws a mark, the other takes brightness away, and neither may ever take a
 * publication off the shelf: "a library that shrinks when the Wi-Fi drops reads as data
 * loss".
 *
 * These are asked once per visible cell on every redraw, which is the other reason they are
 * decided here: a screenshot shows one shelf in one state, and the states that matter are the
 * ones a reader reaches by pulling a card out or walking out of Wi-Fi range.
 */
class LibraryMarksTest {

    private val downloads = File("/data/user/0/app.storyarc/files/downloads")

    private fun publication(title: String, sourceId: UUID? = null) = Publication(
        identity = PublicationIdentity(normalizedPath = "/comics/$title.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = title,
        origin = MetadataOrigin.INFERRED,
        sourceId = sourceId,
    )

    private fun registry(kind: SourceKind, state: SourceConnectionState): Pair<UUID, SourceRegistry> {
        val source = Source(displayName = kind.name, kind = kind, state = state)
        return source.id to SourceRegistry(sources = listOf(source))
    }

    // MARK: - The mark

    @Test
    fun `a copy the app fetched carries the mark`() {
        assertTrue(
            isKeptOnDevice(
                "/data/user/0/app.storyarc/files/downloads/1/Nightjar 1.cbz",
                downloads,
            ),
        )
    }

    @Test
    fun `a file a folder scan found does not`() {
        // On the device, but not *kept* by the app: the card can be pulled and the grant can
        // lapse. Only a copy in the app's own storage carries the offline promise, so only
        // that copy earns the mark. iOS draws the same line.
        assertFalse(isKeptOnDevice("/storage/emulated/0/Comics/Nightjar 1.cbz", downloads))
        assertFalse(isKeptOnDevice("content://com.android.externalstorage.documents/tree/c", downloads))
    }

    @Test
    fun `a sibling folder whose name merely begins with the store's does not`() {
        // The reason the separator is appended before the comparison.
        assertFalse(
            isKeptOnDevice("/data/user/0/app.storyarc/files/downloads-old/1/one.cbz", downloads),
        )
    }

    @Test
    fun `a publication with nowhere recorded does not`() {
        assertFalse(isKeptOnDevice(null, downloads))
        assertFalse(isKeptOnDevice("", downloads))
    }

    @Test
    fun `a view model built with no download store marks nothing`() {
        assertFalse(isKeptOnDevice("/data/user/0/app.storyarc/files/downloads/1/one.cbz", null))
    }

    // MARK: - The dimming

    @Test
    fun `a file with no library behind it is readable`() {
        // It came from another app handing a file over. Attributing it to whichever library
        // happens to be down would be a guess that dimmed it for nothing.
        assertTrue(isReadableNow(publication("one"), "/comics/one.cbz", SourceRegistry()))
    }

    @Test
    fun `a file whose library is not in the registry is readable`() {
        val orphan = publication("one", sourceId = UUID.randomUUID())

        assertTrue(isReadableNow(orphan, "/comics/one.cbz", SourceRegistry()))
    }

    @Test
    fun `a downloaded copy stays readable while its server is away`() {
        // The whole point of downloading. `offline-downloads` promises what has been
        // downloaded stays readable, so a server going down must not dim its copies.
        val (id, registry) = registry(
            SourceKind.KAVITA_SERVER,
            SourceConnectionState.Unreachable(0L),
        )

        assertTrue(
            isReadableNow(
                publication("one", sourceId = id),
                "/data/user/0/app.storyarc/files/downloads/1/one.cbz",
                registry,
            ),
        )
    }

    @Test
    fun `a publication only a server has is dimmed while that server is away`() {
        val (id, registry) = registry(
            SourceKind.KAVITA_SERVER,
            SourceConnectionState.Unreachable(0L),
        )

        assertFalse(
            isReadableNow(publication("one", sourceId = id), "https://library/entry/6", registry),
        )
    }

    @Test
    fun `a publication on a share is dimmed while the share is away`() {
        val (id, registry) = registry(
            SourceKind.NETWORK_SHARE,
            SourceConnectionState.Unreachable(0L),
        )

        assertFalse(
            isReadableNow(publication("one", sourceId = id), "smb://nas/comics/one.cbz", registry),
        )
    }

    @Test
    fun `a folder the system no longer lets the app read dims its files`() {
        // The case Android has and iOS does not. The bytes are still on the device and the
        // app may no longer open them, so a local path is not the last word here.
        val (id, registry) = registry(
            SourceKind.LOCAL_FOLDER,
            SourceConnectionState.Unreachable(0L),
        )

        assertFalse(
            isReadableNow(
                publication("one", sourceId = id),
                "content://com.android.externalstorage.documents/tree/comics/one.cbz",
                registry,
            ),
        )
    }

    @Test
    fun `a folder that is answering does not`() {
        val (id, registry) = registry(SourceKind.LOCAL_FOLDER, SourceConnectionState.Connected)

        assertTrue(
            isReadableNow(
                publication("one", sourceId = id),
                "content://com.android.externalstorage.documents/tree/comics/one.cbz",
                registry,
            ),
        )
    }

    @Test
    fun `a source that has not answered yet dims nothing`() {
        // Every network source is probed when the library appears, and `Connecting` is the
        // state it is in while that runs. Treating "still asking" as "cannot be reached"
        // greys the whole shelf on every launch and un-greys it a second later, which tells
        // the reader their library is broken and then that it is not.
        for (kind in SourceKind.entries) {
            val (id, registry) = registry(kind, SourceConnectionState.Connecting)
            assertTrue(
                kind.name,
                isReadableNow(publication("one", sourceId = id), "smb://nas/one.cbz", registry),
            )
        }
    }

    @Test
    fun `a refused sign-in dims what only that server has`() {
        val (id, registry) = registry(
            SourceKind.KAVITA_SERVER,
            SourceConnectionState.Unauthorized("key revoked"),
        )

        assertFalse(
            isReadableNow(publication("one", sourceId = id), "https://library/entry/6", registry),
        )
    }

    @Test
    fun `a publication no decoder will open is not dimmed for it`() {
        // A different message, carried by the cell's own caption. Dimming it as well would
        // conflate "your network is down" with "this file is a CB7".
        val refused = Publication(
            identity = PublicationIdentity(normalizedPath = "/comics/one.cb7"),
            format = PublicationFormat.CB7,
            displayTitle = "one",
            origin = MetadataOrigin.INFERRED,
            streaming = StreamingCapability.REFUSED,
        )

        assertFalse(refused.isOpenable)
        assertTrue(isReadableNow(refused, "/comics/one.cb7", SourceRegistry()))
    }
}
