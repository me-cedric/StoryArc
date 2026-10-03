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
 *
 * Task 5.1's corrected note: D25 also asks for the request before the first connection to a
 * LAN OPDS catalogue or Kavita server. The four tests below cover those two sheets: the
 * request comes at that connect, and only a LAN address is refused.
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
    private val catalogueConnection: String by lazy { read(CATALOGUE_CONNECTION_SOURCE) }
    private val catalogueSheet: String by lazy { read(CATALOGUE_SHEET_SOURCE) }
    private val kavitaConnection: String by lazy { read(KAVITA_CONNECTION_SOURCE) }
    private val kavitaSheet: String by lazy { read(KAVITA_SHEET_SOURCE) }

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

    @Test
    fun `connecting a catalogue is refused before it is attempted, when a LAN address is blocked`() {
        val body = catalogueConnection.substringAfter("fun connect() {")
        val guard = body.indexOf("waitsOnLocalNetwork(target)")
        val dispatch = body.indexOf("when (target)")
        assertTrue("CatalogueConnection.connect() no longer asks waitsOnLocalNetwork.", guard >= 0)
        assertTrue(
            "The permission is checked after the catalogue or Kavita request would already" +
                " have started, rather than before -- the one case a blocked TCP connect" +
                " times out instead of failing at once.",
            guard in 0..<dispatch,
        )
        assertTrue(
            "A blocked connect must show its own sentence, not a generic failure.",
            body.contains("R.string.catalogue_error_local_network_denied"),
        )
        assertBlocksOnlyALanAddress(catalogueConnection, "CatalogueConnection")
    }

    @Test
    fun `connecting a kavita server is refused before it is attempted, when a LAN address is blocked`() {
        val body = kavitaConnection.substringAfter("fun connect() {")
        val guard = body.indexOf("LocalNetworkPermission.refuses(context, target.base)")
        val connecting = body.indexOf("Step.Connecting")
        assertTrue("KavitaConnection.connect() no longer asks LocalNetworkPermission.refuses.", guard >= 0)
        assertTrue(
            "The permission is checked after the client would already have started" +
                " connecting, rather than before -- the one case a blocked TCP connect" +
                " times out instead of failing at once.",
            guard in 0..<connecting,
        )
        assertTrue(
            "A blocked connect must show its own sentence, not a generic failure.",
            body.contains("R.string.kavita_error_local_network_denied"),
        )
        assertBlocksOnlyALanAddress(kavitaConnection, "KavitaConnection")
    }

    @Test
    fun `the catalogue sheet asks for the permission at the first LAN connect`() =
        assertAsksAtConnect(catalogueSheet, "CatalogueSheet")

    @Test
    fun `the kavita sheet asks for the permission at the first LAN connect`() =
        assertAsksAtConnect(kavitaSheet, "KavitaSheet")

    /** A public server never needs the permission, so a blanket `blocks` would refuse it. */
    private fun assertBlocksOnlyALanAddress(source: String, name: String) {
        assertTrue(
            "$name refuses every address while the permission is blocked, a public one too.",
            !source.contains("LocalNetworkPermission.blocks("),
        )
    }

    private fun assertAsksAtConnect(source: String, name: String) {
        assertTrue(
            "$name no longer requests LocalNetworkPermission.PERMISSION when a connect waits on it.",
            source.contains(
                "if (connection.waitsOnLocalNetwork()) {\n" +
                    "            requestLocalNetwork.launch(LocalNetworkPermission.PERMISSION)",
            ),
        )
        assertTrue(
            "$name asks when it opens, before it knows whether the server is on the LAN.",
            !source.contains("LaunchedEffect(Unit)"),
        )
        assertTrue(
            "$name has a connect button that skips the permission question.",
            !source.contains("onClick = { connection.connect() }"),
        )
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val CONNECTION_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/SmbConnection.kt"
        const val SHEET_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/SmbSheet.kt"
        const val CATALOGUE_CONNECTION_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/CatalogueConnection.kt"
        const val CATALOGUE_SHEET_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/CatalogueSheet.kt"
        const val KAVITA_CONNECTION_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/KavitaConnection.kt"
        const val KAVITA_SHEET_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/KavitaSheet.kt"
    }
}
