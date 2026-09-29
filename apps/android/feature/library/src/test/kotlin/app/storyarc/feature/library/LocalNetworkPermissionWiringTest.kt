package app.storyarc.feature.library

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `network-share` "Local network permission denied" needs the runtime permission asked at
 * the right two moments -- opening discovery, and the first connect -- and
 * [LocalNetworkPermissionTest] cannot see either: both live in a `ViewModel` and a
 * `Composable` that need an SDK 37 Robolectric shadow nothing ships. Read as source instead,
 * the way [SourceRetryWiringTest] does for the same reason.
 */
class LocalNetworkPermissionWiringTest {

    private fun read(path: String): String {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:library:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, path)
        if (!file.isFile) error("$path is not under ${module.absolutePath} — has it moved?")
        return file.readText()
    }

    private val connection: String by lazy { read(CONNECTION_SOURCE) }
    private val sheet: String by lazy { read(SHEET_SOURCE) }

    @Test
    fun `connecting is refused before it is attempted, when local network access is blocked`() {
        val body = connection.substringAfter("fun connect() {")
        val guard = body.indexOf("LocalNetworkPermission.blocks(")
        val connecting = body.indexOf("Step.Connecting")
        assertTrue("connect() no longer asks LocalNetworkPermission.blocks.", guard >= 0)
        assertTrue(
            "The permission is checked after the client would already have started" +
                " connecting, rather than before -- the one case a blocked TCP connect" +
                " times out instead of failing at once.",
            guard in 0..<connecting,
        )
        assertTrue(
            "A blocked connect must show its own sentence, not smb_error_unexpected.",
            body.contains("R.string.smb_error_local_network_denied"),
        )
    }

    @Test
    fun `the add-share sheet asks for the permission at the moment discovery is first needed`() {
        assertTrue(
            "SmbSheet no longer requests LocalNetworkPermission.PERMISSION.",
            sheet.contains("requestLocalNetwork.launch(LocalNetworkPermission.PERMISSION)"),
        )
        assertTrue(
            "A denied permission must hide discovery behind its own explanation, not an" +
                " empty list with no reason given.",
            sheet.contains("R.string.smb_discovery_local_network_denied"),
        )
        assertTrue(
            "Discovery must stop calling SmbDiscovery.hosts once blocked, or a denied" +
                " permission still starts NsdManager discovery.",
            sheet.contains("if (discoveryBlocked) emptyFlow() else SmbDiscovery.hosts(context)"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val CONNECTION_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/SmbConnection.kt"
        const val SHEET_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/SmbSheet.kt"
    }
}
