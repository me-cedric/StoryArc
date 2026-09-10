package app.storyarc.feature.library

import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasProgressBarRangeInfo
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.kavita.KavitaAddress
import app.storyarc.core.persistence.KavitaProgressStore
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * A server that has been asked and has not answered says so.
 *
 * A reader added a Kavita server and met a blank page. The list was empty because the request
 * had not returned, and nothing on screen could tell that from a server with no libraries in
 * it. `KavitaClient` waits twenty seconds before it gives up, so the blank page lasted that
 * long, and one level deeper the page went further and stated the library was empty.
 *
 * The server here accepts the connection and never answers, which is the state under test:
 * not a failure, which the screen already explains, but the silence before one.
 *
 * `GraphicsMode.NATIVE` and `sdk = [34]` for the reasons [KavitaCardFactsTest] gives.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34])
class KavitaWaitingTest {

    @get:Rule
    val compose = createComposeRule()

    private lateinit var server: HttpServer

    /** Held for the length of the test, so no request can complete inside it. */
    private val held = CountDownLatch(1)

    @Before
    fun start() {
        server = HttpServer.create(InetSocketAddress("localhost", 0), 0)
        server.createContext("/") { held.await(30, TimeUnit.SECONDS) }
        server.start()
    }

    @After
    fun stop() {
        held.countDown()
        server.stop(0)
    }

    @Test
    fun `a server that has not answered is drawn as waiting and not as empty`() {
        compose.setContent {
            StoryArcTheme {
                KavitaBrowserScreen(
                    title = "Kavita",
                    address = KavitaAddress("http://localhost:${server.address.port}", "key"),
                    sourceId = "kavita-waiting",
                    store = KavitaProgressStore.open(ApplicationProvider.getApplicationContext()),
                    level = KavitaLevel.Libraries,
                    onLevel = {},
                    onOpen = { _, _ -> },
                    onBack = {},
                )
            }
        }

        compose
            .onNode(hasProgressBarRangeInfo(ProgressBarRangeInfo.Indeterminate))
            .assertIsDisplayed()
    }
}
