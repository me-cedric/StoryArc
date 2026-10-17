// How the renderer talks to the host that embeds it, one function per direction.
//
// Out: `post(message)` hands a plain JSON object to the host. Each web view has its own
// door for it and the bundle picks the one that exists, so the same file runs in all three:
//
//   WKWebView (macOS) and WebKitGTK (Linux)  window.webkit.messageHandlers.storyarc
//   WebView2 (Windows)                        window.chrome.webview
//
// Nothing here opens a connection. A page with no host (a browser tab, a test) gets a post
// that drops the message, and `open` takes a `post` of its own for the host that wants one.
//
// In: the host calls `StoryArcEpub.receive(message)` on the reader it opened.

export const HANDLER = 'storyarc'

/** @param {typeof globalThis} [scope] */
export function hostPost(scope = globalThis) {
  const handler = scope.webkit?.messageHandlers?.[HANDLER]
  if (handler) return (message) => handler.postMessage(message)
  const webview = scope.chrome?.webview
  if (webview) return (message) => webview.postMessage(message)
  return () => {}
}

/**
 * Stamps every message with a sequence number, so a host that handles messages out of order
 * (an async bridge) can tell a stale locator from a current one.
 */
export function sequenced(post) {
  let seq = 0
  return (message) => {
    seq += 1
    post({ ...message, seq })
  }
}
