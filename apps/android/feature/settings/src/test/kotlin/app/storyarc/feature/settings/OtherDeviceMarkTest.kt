package app.storyarc.feature.settings

import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * `library-sync` task 5.8: Your libraries marks a source that a sync brought from another device,
 * and says when its address names that device.
 */
class OtherDeviceMarkTest {

    private val share = Source(displayName = "Share", kind = SourceKind.NETWORK_SHARE, locator = "smb://nas.local/Comics")

    @Test
    fun `a source this device added carries no mark`() {
        assertNull(otherDeviceMark(share))
        assertNull(otherDeviceMark(share.copy(locator = "smb://127.0.0.1:4448/Sync")))
    }

    @Test
    fun `a source from another device is marked, and a loopback one says it is not tried`() {
        assertEquals(R.string.sources_other_device, otherDeviceMark(share.copy(fromAnotherDevice = true)))
        assertEquals(
            R.string.sources_other_device_loopback,
            otherDeviceMark(share.copy(fromAnotherDevice = true, locator = "smb://127.0.0.1:4448/Sync")),
        )
    }
}
