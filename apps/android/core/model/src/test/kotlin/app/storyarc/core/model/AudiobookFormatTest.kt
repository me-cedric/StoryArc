package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The formats that open in a player rather than in a reader.
 *
 * `publication-formats` adds three rows to the table it already had — an M4B, a folder of
 * ordered audio files, and a single audio file "as a one-part audiobook" — and one
 * scenario that decides how they are modelled: "an `.m4b` and an `.m4a` holding the same
 * audio are treated identically, because the extension is a hint and the contents are the
 * fact". So the enum carries **containers**, detected from bytes, and not the two
 * extensions Apple happens to use for one of them.
 *
 * iOS's `AudiobookFormatTests` asserts the same table.
 */
class AudiobookFormatTest {

    private val audio = listOf(
        PublicationFormat.M4B,
        PublicationFormat.MP3,
        PublicationFormat.FLAC,
        PublicationFormat.OGG,
        PublicationFormat.AUDIO_FOLDER,
    )

    private val reading = listOf(
        PublicationFormat.CBZ,
        PublicationFormat.CBR,
        PublicationFormat.CB7,
        PublicationFormat.CBT,
        PublicationFormat.EPUB,
        PublicationFormat.PDF,
        PublicationFormat.IMAGE_FOLDER,
    )

    @Test
    fun `the table is these twelve and nothing else`() {
        // A guard against a case added without an answer here: every property below is an
        // exhaustive `when`, so a thirteenth format is a compile error there — and this is
        // what fails if somebody adds one and answers `else`.
        assertEquals(audio.size + reading.size, PublicationFormat.entries.size)
    }

    @Test
    fun `an audio format opens in the player`() {
        for (format in audio) assertTrue(format.name, format.isAudio)
        for (format in reading) assertFalse(format.name, format.isAudio)
    }

    @Test
    fun `audio is never paged images`() {
        // The property that decides which reader opens a publication. An audiobook has no
        // pages, so a `true` here would send it to the comic reader.
        for (format in audio) assertFalse(format.name, format.isPagedImages)
    }

    @Test
    fun `an audiobook is openable`() {
        // CB7 is the only format that parses and does not open. A protected audiobook is
        // refused by the *sniffer*, before a format is ever assigned — see
        // `FormatSniffer.Container.PROTECTED_AUDIOBOOK` — so there is no locked format
        // here to mark unopenable, and inventing one would let a locked file be listed.
        for (format in audio) assertTrue(format.name, format.isOpenable)
    }

    @Test
    fun `every audio file format round-trips through its media type`() {
        // `local-library`'s imported copies store a media type and work the file's
        // extension back out of it, so a format whose type does not round-trip is a copy
        // the app can no longer find. This is the whole reason the enum carries containers
        // rather than one flat `AUDIOBOOK`: `audio/mpeg` has to come back as `MP3`.
        for (format in audio - PublicationFormat.AUDIO_FOLDER) {
            val mediaType = format.mediaType
            assertNotNull(format.name, mediaType)
            assertEquals(format.name, format, PublicationFormat.ofMediaType(mediaType!!))
        }
    }

    @Test
    fun `a folder has no media type of its own`() {
        // The same answer `IMAGE_FOLDER` gives, and for the same reason: a folder is not a
        // file and has no type.
        assertNull(PublicationFormat.AUDIO_FOLDER.mediaType)
    }

    @Test
    fun `an m4a and an m4b are one format`() {
        // The scenario, as a type assertion. Both are `audio/mp4`, so both index as `M4B`
        // and nothing downstream can tell them apart — which is what "treated identically"
        // means when the extension is only ever a hint.
        assertEquals(PublicationFormat.M4B, PublicationFormat.ofMediaType("audio/mp4"))
        assertEquals(PublicationFormat.M4B, PublicationFormat.ofMediaType("audio/x-m4b"))
        assertEquals(PublicationFormat.M4B, PublicationFormat.ofMediaType("audio/x-m4a"))
    }

    @Test
    fun `a media type with parameters still names its format`() {
        // Several servers append a charset even to audio. An exact-match table would call
        // that unreadable, which is the bug this already fixed once for EPUB.
        assertEquals(PublicationFormat.MP3, PublicationFormat.ofMediaType("audio/mpeg; charset=utf-8"))
    }

    @Test
    fun `every audio format has a name to refuse or filter by`() {
        for (format in audio) assertTrue(format.name, format.displayName.isNotBlank())
        assertEquals("M4B", PublicationFormat.M4B.displayName)
        assertEquals("Audiobook folder", PublicationFormat.AUDIO_FOLDER.displayName)
    }
}
