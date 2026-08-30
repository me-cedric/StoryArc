package app.storyarc.feature.epubreader

import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayInputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Whether a publication can reach the network from inside the reader's web view.
 *
 * ADR-0015. An EPUB is HTML, and HTML that is merely being read can still fetch: a
 * tracking pixel, a script's `fetch`, a `sendBeacon`, a socket, a frame, a redirect.
 * None of it needs the reader to touch anything, and the host on the other end learns
 * the device's address, the moment of reading and — through a URL the publication's
 * author chose — which book.
 *
 * Instrumented because the thing under test is the system WebView, which the
 * unit-test `android.jar` stubs away. Hermetic: the listener is a socket on the
 * device's own loopback, so nothing leaves the emulator and the test needs no
 * network. The beacons use `https` for the reason the app forbids cleartext — a plain
 * `http` request would be refused by the platform before the block was consulted, and
 * the test would then pass without proving anything. The handshake fails, there being
 * no certificate; the connection is accepted first, which is the whole question.
 *
 * [controlAPublicationReachesTheNetworkWhenNothingStopsIt] is the half that fails
 * against the code before ADR-0015: every vector arrives.
 *
 * Method names are camelCase for the reason `TableOfContentsTest` gives — dex refuses
 * a method name holding a space.
 */
class PublicationEgressTest {

    /** Mirrors Readium's own origin: `WebViewServer.PACKAGE_HOSTNAME` is this string. */
    private val origin = "https://readium_package"

    private val vectors = listOf(
        "img", "script-img", "fetch", "xhr", "beacon", "websocket", "iframe", "navigation",
    )

    @Test
    fun controlAPublicationReachesTheNetworkWhenNothingStopsIt() {
        val run = render(deny = false)

        assertTrue(
            "the page never loaded, so the run proves nothing: ${run.served}",
            run.served.any { it.endsWith("/style.css") },
        )
        assertEquals("every vector should arrive unblocked", vectors.sorted(), run.reached)
    }

    @Test
    fun denyingEgressStopsEveryVector() {
        val run = render(deny = true)

        assertTrue(
            "the publication's own resources must still be served: ${run.served}",
            run.served.any { it.endsWith("/style.css") },
        )
        assertEquals("nothing may reach the network", emptyList<String>(), run.reached)
    }

    // MARK: - Harness

    private class Run(val served: List<String>, val reached: List<String>)

    /**
     * Loads a page that tries every way an EPUB has of reaching a host, and reports
     * what the publication's own origin served and which vectors arrived.
     */
    private fun render(deny: Boolean): Run {
        val sockets = vectors.associateWith {
            ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))
        }
        val reached = Collections.synchronizedSet(mutableSetOf<String>())
        sockets.forEach { (name, socket) ->
            Thread {
                try {
                    while (true) {
                        socket.accept().close()
                        reached += name
                    }
                } catch (_: Exception) {
                    // The socket was closed at the end of the run.
                }
            }.apply { isDaemon = true }.start()
        }
        val port = { name: String -> sockets.getValue(name).localPort }

        val served = Collections.synchronizedList(mutableListOf<String>())
        val loaded = CountDownLatch(1)
        val instrumentation = InstrumentationRegistry.getInstrumentation()

        instrumentation.runOnMainSync {
            val context = instrumentation.targetContext
            val webView = WebView(context)
            // A container, because the production hook is handed a fragment's root view
            // rather than the web view itself.
            val root = FrameLayout(context).apply { addView(webView) }

            webView.settings.javaScriptEnabled = true
            // Stands in for Readium's client, which serves the publication and its own
            // scripts from this callback and declines everything else.
            webView.webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(
                    view: WebView,
                    request: WebResourceRequest,
                ): WebResourceResponse? {
                    val url = request.url.toString()
                    if (!url.startsWith(origin)) return null
                    served += url
                    return when {
                        url.endsWith("/style.css") -> response("text/css", "p{color:red}")
                        else -> response("text/html", page(port))
                    }
                }

                override fun onPageFinished(view: WebView, url: String) = loaded.countDown()
            }

            webView.loadUrl("$origin/publication/index.xhtml")
            // Deliberately after the load is issued. Readium calls `loadUrl` inside
            // `R2EpubPageFragment.onCreateView`, so the fragment-view callback the app
            // hooks is the earliest it can reach the web view — and this test would be
            // worthless if it installed the block any earlier than production does.
            if (deny) {
                PublicationEgress.deny(root)
            }
        }

        loaded.await(15, TimeUnit.SECONDS)
        // The beacons fire from a script, and the last of them is a navigation on a
        // timer. A refused connection is quicker than an accepted one, so the wait has
        // to be long enough that the control cannot pass for being slow.
        Thread.sleep(5_000)
        sockets.values.forEach { it.close() }

        return Run(served.toList(), reached.sorted())
    }

    private fun response(mediaType: String, body: String) =
        WebResourceResponse(mediaType, "utf-8", ByteArrayInputStream(body.toByteArray()))

    private fun page(port: (String) -> Int) =
        """
        <!doctype html><html><head>
        <link rel="stylesheet" href="$origin/publication/style.css">
        </head><body><p>text</p>
        <img src="https://127.0.0.1:${port("img")}/pixel.png">
        <script>
        new Image().src = "https://127.0.0.1:${port("script-img")}/pixel.png";
        fetch("https://127.0.0.1:${port("fetch")}/f").catch(function (e) {});
        var x = new XMLHttpRequest();
        x.open("GET", "https://127.0.0.1:${port("xhr")}/x");
        try { x.send(); } catch (e) {}
        if (navigator.sendBeacon) {
          try { navigator.sendBeacon("https://127.0.0.1:${port("beacon")}/b", "x"); } catch (e) {}
        }
        try { new WebSocket("wss://127.0.0.1:${port("websocket")}/s"); } catch (e) {}
        var f = document.createElement("iframe");
        f.src = "https://127.0.0.1:${port("iframe")}/frame";
        document.body.appendChild(f);
        setTimeout(function () {
          location.href = "https://127.0.0.1:${port("navigation")}/go";
        }, 1500);
        </script>
        </body></html>
        """.trimIndent()
}
