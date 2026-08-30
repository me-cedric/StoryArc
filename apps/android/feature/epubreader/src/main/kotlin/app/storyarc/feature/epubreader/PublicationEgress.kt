package app.storyarc.feature.epubreader

import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Message
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.ClientCertRequest
import android.webkit.HttpAuthHandler
import android.webkit.RenderProcessGoneDetail
import android.webkit.SafeBrowsingResponse
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * Stops a publication reaching the network.
 *
 * ADR-0015. A reflowable EPUB is HTML rendered in a real web view, and HTML that is
 * only being read can still fetch: a one-pixel image, a script's `fetch`, a
 * `sendBeacon`, a socket, a frame, a redirect. None of it needs the reader to touch
 * anything, and the host on the other end learns the address, the moment, and —
 * through a URL the publication's author chose — which book and which chapter.
 * `README.md` promises data leaves the device only for sources the reader
 * configured, and a publication is not one of them.
 *
 * Two levers, because measurement said one was not enough. `PublicationEgressTest`
 * fires eight vectors at a listener on the device's own loopback:
 *
 *  - [android.webkit.WebSettings.setBlockNetworkLoads] refuses seven of them —
 *    images, scripted images, `fetch`, `XMLHttpRequest`, `sendBeacon`, frames and
 *    top-level navigation. A web socket goes out anyway: it is not a resource load,
 *    so it never reaches the loader this setting guards.
 *  - A `Content-Security-Policy: connect-src 'none'` response header closes the
 *    socket, and `fetch`, `XHR` and `sendBeacon` a second time. It is one directive
 *    on purpose: it governs the connecting APIs and nothing else, so no image, style,
 *    script or font that the reader is meant to see can be affected by it.
 *
 * Nothing Readium does is touched. It answers every request for the publication and
 * for its own scripts from `WebViewClient.shouldInterceptRequest`, which is consulted
 * before the loader, and none of `readium-reflowable.js` or `readium-fixed.js` opens
 * a connection — the navigator talks to the app through a JavaScript interface.
 *
 * What it costs: a publication that genuinely references a remote font, image or
 * stylesheet loses it. That is deliberate. Those are not features of this app; a
 * publication reaching out is the defect. Nothing is said about it on screen — the
 * posture is recorded in the repository, not in the reader's page.
 *
 * Scripting stays on. Readium drives pagination, locators, decorations and selection
 * through injected scripts, and a publication's own scripts are part of what it
 * renders. Blocking egress is not the same as blocking scripting, and only the first
 * is free.
 */
internal object PublicationEgress {

    /**
     * Governs `fetch`, `XMLHttpRequest`, `WebSocket`, `EventSource` and
     * `navigator.sendBeacon`. Deliberately the only directive: a wider policy would
     * start deciding what the reader may see, and `blockNetworkLoads` already decides
     * what may be fetched.
     */
    private const val POLICY = "connect-src 'none'"

    private const val HEADER = "Content-Security-Policy"

    /**
     * Applied to every web view under [root], because the app is handed a fragment's
     * view rather than Readium's web view.
     *
     * Written against `android.webkit` alone and against no Readium type: the
     * navigator draws one page fragment per resource, and the only thing that can be
     * relied on across toolkit versions is that a page is drawn by a [WebView].
     *
     * Called from the fragment-view callback, which is the earliest the app can reach
     * a page — Readium calls `loadUrl` inside its own `onCreateView`. The test covers
     * that ordering: it installs the same way, after the load is issued, and the
     * first document still carries the policy.
     */
    fun deny(root: View) {
        forEachWebView(root) { webView ->
            webView.settings.blockNetworkLoads = true
            val client = webView.webViewClient
            if (client !is Restricted) {
                webView.webViewClient = Restricted(client)
            }
        }
    }

    private fun forEachWebView(view: View, apply: (WebView) -> Unit) {
        when (view) {
            is WebView -> apply(view)
            is ViewGroup ->
                for (index in 0 until view.childCount) {
                    forEachWebView(view.getChildAt(index), apply)
                }
        }
    }

    /**
     * Readium's own client, with the policy added to everything it serves.
     *
     * Every method is forwarded rather than only the four Readium overrides today, so
     * that a toolkit which starts answering a fifth keeps working. The deprecated
     * `String` overloads are left out: the framework calls the `WebResourceRequest`
     * ones from API 21, and this module's floor is 31.
     */
    private class Restricted(private val client: WebViewClient) : WebViewClient() {

        override fun shouldInterceptRequest(
            view: WebView,
            request: WebResourceRequest,
        ): WebResourceResponse? {
            val response = client.shouldInterceptRequest(view, request) ?: return null
            response.responseHeaders =
                (response.responseHeaders ?: emptyMap()) + mapOf(HEADER to POLICY)
            return response
        }

        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) =
            client.shouldOverrideUrlLoading(view, request)

        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) =
            client.onPageStarted(view, url, favicon)

        override fun onPageFinished(view: WebView, url: String) =
            client.onPageFinished(view, url)

        override fun onPageCommitVisible(view: WebView, url: String) =
            client.onPageCommitVisible(view, url)

        override fun onLoadResource(view: WebView, url: String) =
            client.onLoadResource(view, url)

        override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) =
            client.doUpdateVisitedHistory(view, url, isReload)

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: WebResourceError,
        ) = client.onReceivedError(view, request, error)

        override fun onReceivedHttpError(
            view: WebView,
            request: WebResourceRequest,
            errorResponse: WebResourceResponse,
        ) = client.onReceivedHttpError(view, request, errorResponse)

        override fun onReceivedSslError(
            view: WebView,
            handler: SslErrorHandler,
            error: SslError,
        ) = client.onReceivedSslError(view, handler, error)

        override fun onReceivedClientCertRequest(view: WebView, request: ClientCertRequest) =
            client.onReceivedClientCertRequest(view, request)

        override fun onReceivedHttpAuthRequest(
            view: WebView,
            handler: HttpAuthHandler,
            host: String,
            realm: String,
        ) = client.onReceivedHttpAuthRequest(view, handler, host, realm)

        override fun onReceivedLoginRequest(
            view: WebView,
            realm: String,
            account: String?,
            args: String,
        ) = client.onReceivedLoginRequest(view, realm, account, args)

        override fun onFormResubmission(view: WebView, dontResend: Message, resend: Message) =
            client.onFormResubmission(view, dontResend, resend)

        override fun onScaleChanged(view: WebView, oldScale: Float, newScale: Float) =
            client.onScaleChanged(view, oldScale, newScale)

        override fun shouldOverrideKeyEvent(view: WebView, event: KeyEvent) =
            client.shouldOverrideKeyEvent(view, event)

        override fun onUnhandledKeyEvent(view: WebView, event: KeyEvent) =
            client.onUnhandledKeyEvent(view, event)

        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail) =
            client.onRenderProcessGone(view, detail)

        override fun onSafeBrowsingHit(
            view: WebView,
            request: WebResourceRequest,
            threatType: Int,
            callback: SafeBrowsingResponse,
        ) = client.onSafeBrowsingHit(view, request, threatType, callback)
    }
}
