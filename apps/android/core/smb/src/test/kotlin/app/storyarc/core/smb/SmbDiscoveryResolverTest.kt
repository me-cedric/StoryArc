package app.storyarc.core.smb

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * One resolve listener per resolve, which is the rule that keeps a second host from taking
 * the app down.
 *
 * `NsdManager` keeps a resolve listener in a map keyed by the instance and removes it only
 * when that resolve succeeds or fails, so a second `resolveService` handed the same instance
 * throws `IllegalArgumentException("listener already in use")` on `NsdManager`'s own callback
 * thread. Nothing catches it there, so the app goes down.
 *
 * Read as source, the way [LocalNetworkPermissionWiringTest] reads its own wiring for the
 * same reason: `NsdManager` and `NsdServiceInfo` need an SDK 37 Robolectric shadow that this
 * module does not ship, and `:core:smb` has JUnit alone. The rule this guards is an identity
 * rule about a framework call, so there is nothing to assert on a value instead.
 *
 * [FoundHostsTest] covers the part that is a value: the table of hosts itself.
 */
class SmbDiscoveryResolverTest {

    private val discovery: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :core:smb:testDebugUnitTest`), which sets the property" +
                    " from the module directory.",
            )
        val file = File(module, DISCOVERY_SOURCE)
        if (!file.isFile) error("$DISCOVERY_SOURCE is not under ${module.absolutePath} — has it moved?")
        file.readText()
    }

    @Test
    fun `every resolve is handed a listener of its own`() {
        assertTrue(
            "SmbDiscovery no longer builds a resolve listener per call. A listener shared" +
                " between two resolves throws IllegalArgumentException(\"listener already in" +
                " use\") on NsdManager's callback thread, which crashes the app the moment a" +
                " second share answers.",
            discovery.contains("manager.resolveService(info, resolver())"),
        )
    }

    @Test
    fun `the listener is built inside the resolve call, not hoisted beside the discovery one`() {
        // The shape of the defect, not merely its symptom: the old code held one `resolver`
        // in the flow's scope and passed that same object every time. A future edit that
        // hoists it back would read as tidier and would restore the crash, so the position
        // is what this asserts.
        val found = discovery.indexOf("override fun onServiceFound")
        assertTrue("SmbDiscovery no longer handles onServiceFound.", found >= 0)

        val declaration = discovery.indexOf("fun resolver(): NsdManager.ResolveListener")
        assertTrue(
            "The resolve listener is no longer a function. A `val resolver = object : ...`" +
                " is one instance for every resolve, which is the crash this guards.",
            declaration >= 0,
        )
        assertTrue(
            "The listener must be built per call. `resolver` is handed to resolveService as" +
                " a value rather than called, so every resolve shares one instance.",
            !discovery.contains("manager.resolveService(info, resolver)"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.smb.projectDir"
        const val DISCOVERY_SOURCE = "src/main/kotlin/app/storyarc/core/smb/SmbDiscovery.kt"
    }
}
