package app.storyarc.core.model

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `library-sync` task 5.8: a source that a sync brought from another device is marked, and its
 * loopback address is known as one that names that device.
 */
class OtherDeviceTest {

    private fun source(name: String, kind: SourceKind, locator: String) =
        Source(displayName = name, kind = kind, locator = locator)

    @Test
    fun `a source the sync brought is marked, and a source this device added is not`() = runTest {
        val place = MemoryPlace()
        val simulator = source("Simulator share", SourceKind.NETWORK_SHARE, "smb://127.0.0.1:4448/Comics")
        val own = source("Kitchen NAS", SourceKind.NETWORK_SHARE, "smb://nas.local/Comics")
        val ios = SyncDevice("ios", LibrarySnapshot(sources = SourceRegistry(listOf(simulator))))
        val android = SyncDevice("android", LibrarySnapshot(sources = SourceRegistry(listOf(own))))

        ios.sync(place, moment(1))
        android.sync(place, moment(2))
        ios.sync(place, moment(3))

        val here = android.library.sources
        assertTrue(here[simulator.id]!!.fromAnotherDevice)
        assertTrue(here[simulator.id]!!.reachesOnlyAnotherDevice)
        assertFalse(here[own.id]!!.fromAnotherDevice)
        assertFalse(ios.library.sources[simulator.id]!!.fromAnotherDevice)
        assertTrue(ios.library.sources[own.id]!!.fromAnotherDevice)
        assertFalse(ios.library.sources[own.id]!!.reachesOnlyAnotherDevice)
    }

    @Test
    fun `a loopback address is one that names the device it is used on`() {
        val loopback = listOf(
            "smb://127.0.0.1:4448/Sync",
            "smb://reader@127.0.0.1/Sync",
            "http://localhost:5000",
            "https://LOCALHOST/opds",
            "http://[::1]:5000/",
            "127.0.0.2/Comics",
        )
        val elsewhere = listOf("smb://192.168.1.20/Comics", "https://kavita.example", "http://10.0.2.2:5000", null)

        for (locator in loopback) assertTrue(locator, OtherDevice.isLoopback(locator))
        for (locator in elsewhere) assertFalse(locator.toString(), OtherDevice.isLoopback(locator))
    }

    @Test
    fun `a loopback address this device added is its own and is tried`() {
        val own = source("Local Kavita", SourceKind.KAVITA_SERVER, "http://127.0.0.1:5000")
        assertFalse(own.reachesOnlyAnotherDevice)
        assertEquals(true, own.copy(fromAnotherDevice = true).reachesOnlyAnotherDevice)
    }
}
