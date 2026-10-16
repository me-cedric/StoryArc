# Desktop EPUB hosts: serving archive bytes through a custom scheme, with ranges

**Task 1.27 of `desktop-clients`. Written 2026-10-16 on paper, from vendor documentation. No
web view has run yet; each "Verified" below is Known from the vendor's text, each "Open" waits
for the host spike that the Windows and Linux tasks name.** Confidence labels follow ADR-0005.

The question, from [`design.md`](../openspec/changes/desktop-clients/design.md) Decision 6: every
desktop serves a publication's resources out of its archive through a custom scheme, denies
everything else, and adds a Content-Security-Policy header. The two Rust-side hosts had an open
question each: can WebView2 answer a custom-scheme request with a partial response, and does
WebKitGTK let the handler set a status and headers at all, and do subresources of a page loaded
through the scheme reach the handler.

## WebView2 (Windows)

| Question | Answer | Confidence |
| --- | --- | --- |
| Does a request on a registered custom scheme reach the app? | Yes. A scheme registered through `CoreWebView2CustomSchemeRegistration` on the environment makes `WebResourceRequested` fire for its requests; the registration is immutable for the browser process's lifetime, and the scheme takes part in CORS and obeys CSP | **Known** (Microsoft Learn, the class reference) |
| Can the app answer with a status, a reason and raw headers? | Yes. `CoreWebView2Environment.CreateWebResourceResponse(Stream content, int statusCode, string reasonPhrase, string headers)` takes the raw header block, newline-delimited, so `206 Partial Content` with `Content-Range`, and `Content-Security-Policy` on every response, are expressible | **Known** (the method's reference page) |
| Does the engine send `Range` on a custom scheme, and must the host honour it? | Microsoft's own guidance says a request for a `<video>` may carry a `Range` header and the host should answer with only that span and a matching `Content-Range`, as an HTTP server would. So ranges are expected on the custom scheme, which is what a large EPUB's audio or video needs | **Known** (Microsoft Learn, "Custom management of network requests") |
| Streams | The content stream must hold all of its data by the time the event deferral completes, and should be agile or created off the UI thread. A per-range slice over the core's `RandomAccessSource` satisfies both: one small stream per request, built on a worker | **Known** (the response reference) |

**What the Windows spike still has to run** (task 4.16): that the navigator's own `fetch` of
chapter resources arrives with the scheme's origin, that the deny rule (a `WebResourceRequested`
filter on `*` that refuses every non-scheme URL) and the CSP header stop the eight vectors, and
that seeking a `<video>` produces a second ranged request rather than a full re-read.

## WebKitGTK (Linux)

| Question | Answer | Confidence |
| --- | --- | --- |
| Can the handler set a status and headers? | Yes, since WebKitGTK 2.36: `WebKitURISchemeResponse` has `set_status`, `set_content_type` and `set_http_headers` (a `SoupMessageHeaders`), and `webkit_uri_scheme_request_finish_with_response` returns it. The floor is 2.44, so the API is present on every target | **Known** (the WebKitGTK reference for `URISchemeResponse` and `URISchemeRequest.finish_with_response`) |
| Content length | The response carries a `stream-length` property; `-1` means unknown. Whether that alone sets `Content-Length` is not stated | **Open** |
| Does the engine send `Range` on a custom scheme? | Not documented for WebKitGTK. For Apple's `WKURLSchemeHandler`, a WebKit bug (203302) reports that media requests reached the handler **without** `Range` headers and the whole file was requested repeatedly. The two ports share the engine but not the port layer, so this is a warning, not an answer | **Reported** (WebKit Bugzilla), **Open** for GTK |
| Do a page's subresources use the handler? | Not documented. The spike loads a chapter through the scheme and counts handler calls for its images, styles and fonts | **Open** |
| Denying egress | `WebKitUserContentFilterStore` compiles the same JSON rule list iOS uses; the design marks the match as Inferred. The CSP header is the second lock | **Inferred**, per `design.md` |

**What the Linux spike still has to run** (task 4.10): the eight-vector page on the oldest
WebKitGTK the floor allows (2.44 on Ubuntu 24.04, in the container) and on the Flatpak runtime,
plus the two **Open** rows above, with the handler-call count and the `Range` observation
written into this file.

## macOS, for completeness

`WKURLSchemeHandler` and `WKContentRuleList` are the lever ADR-0015 already measured on iOS,
and the same bug 203302 above says a media element may not send `Range` through the handler, so
the macOS host (task 4.5) records the same observation for audio inside an EPUB.

## What this changes in the design

Nothing in Decision 6 is contradicted. Both Rust-side hosts can express a `206` with
`Content-Range` and a CSP header; whether the engine asks for ranges at all is the one fact only
a running web view can give, and both spikes now name it.

Sources read on 2026-10-16: Microsoft Learn, `CoreWebView2CustomSchemeRegistration` class and
`CoreWebView2Environment.CreateWebResourceResponse`; Microsoft Learn, "Custom management of
network requests in WebView2"; webkitgtk.org reference, `URISchemeResponse` and
`URISchemeRequest.finish_with_response`; WebKit Bugzilla 203302.
