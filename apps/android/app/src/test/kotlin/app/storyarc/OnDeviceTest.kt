package app.storyarc

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What the on-device destination will and will not put on its shelf.
 *
 * `offline-downloads`: "the device has no network at all … this destination is complete and
 * fully functional, with nothing dimmed and nothing waiting". The whole promise reduces to
 * this predicate, and it is the one part of the destination decidable without a device — so
 * it is decided here rather than by looking at a shelf on an emulator and hoping.
 *
 * The case that matters is the share. A publication on a shared folder is in the library, is
 * listed like any other, and is exactly the thing that stops working on a plane; putting one
 * on this shelf would break the destination's only promise on the one journey it exists for.
 */
class OnDeviceTest {

    @Test
    fun `a scanned file is on this device`() {
        assertTrue(isOnDevice("/storage/emulated/0/Comics/Nightjar 1.cbz"))
    }

    @Test
    fun `a document the reader picked is on this device`() {
        assertTrue(isOnDevice("content://com.android.externalstorage.documents/tree/comics"))
        assertTrue(isOnDevice("file:///data/user/0/app.storyarc/files/downloads/1/one.cbz"))
    }

    @Test
    fun `a publication on a shared folder is not`() {
        assertFalse(isOnDevice("smb://nas.local/comics/Nightjar%201.cbz"))
    }

    @Test
    fun `a publication only a server has is not`() {
        assertFalse(isOnDevice("https://library.example/opds/entry/6"))
        assertFalse(isOnDevice("http://library.example/opds/entry/6"))
    }

    @Test
    fun `a publication with nowhere recorded is not`() {
        assertFalse(isOnDevice(null))
        assertFalse(isOnDevice(""))
    }
}
