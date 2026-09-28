## Context

`docs/delivery/remaining-work-2026-09-28.md` lists 225 build items across the
seventeen main capabilities and four open changes. 35 of them waited on an
owner decision; the owner's rulings are recorded whole in this repo's
scratchpad decisions file and reproduced here as D1–D35 and LL, each with the
concrete approach per platform. The owner's rule for every decision: take the
choice with the most features that stays true to the Apple Human Interface
Guidelines, Material 3 and each platform's own best practice — difficulty and
time are never a reason to refuse a choice. See `proposal.md` for why this
change exists and which capabilities it touches; see `tasks.md` for the task
that builds each decision.

Platform floors, from `AGENTS.md` §4: iOS 26.1 minimum, latest SDK, Liquid
Glass with no compatibility shims. Android API 31 minimum, target API 37,
Material 3 Expressive.

## Goals / Non-Goals

**Goals:**
- Record the concrete, per-platform approach for each of the 35 owner
  decisions plus the local-library "unreachable" wording decision (LL), so
  `tasks.md` can cite one line per task instead of re-deriving the approach.
- Name the platform framework and version wherever a decision depends on one,
  and mark anything unverified as Assumed.
- Record the D11 threshold precisely, because it is a number a test asserts.
- Record which items wait on an owner step outside code, so a ticked task
  list is never mistaken for a shipped feature.

**Non-Goals:**
- Re-deriving the 225-item audit or its evidence lines — that is
  `docs/delivery/remaining-work-2026-09-28.md`.
- The fifteen possible additions and the ADR/security-review deferrals listed
  in `proposal.md` Non-goals.
- A migration plan in the usual sense: nothing here changes a stored schema
  a rollback would need to reverse, except where a decision says so (D24's
  Android hand-over table, D26's SMB client swap). Those are called out under
  their own decision below.

## Decisions

Each entry is one owner decision. "Spec impact" repeats what `proposal.md`
already states for the eight that need one; the rest change code only.

### D1 — iOS shelf with no artwork (`collections-and-reading-lists`, `a-server-shelf-shows-what-it-holds` 5b.2)

iOS: draw the existing `CoverlessWell` (SwiftUI view, `CoverlessWell.swift`)
with the format of the first shelf member that has a known format, falling
back to a well with no format symbol when none does. Carry the shelf name on
the well, matching `ShelfCover.kt` on Android. No new type. Spec impact: none.

### D2 — Kavita mark read/unread (`kavita-server`)

Both platforms call Kavita's documented routes `Reader/mark-multiple-read`
and `Reader/mark-multiple-unread` with `seriesId`, `volumeIds` and
`chapterIds`, read from Kavita's published OpenAPI document rather than
guessed — **Assumed** until that document is read against the owner's Kavita
version, because request-body shape is what item 12.3 says STATUS and the
mock both refuse to guess. Extend `scripts/kavita-server.mjs` to answer both
routes. On a `404`, drop the mark from the queue and state on the screen that
made it that this server version does not accept it. Live verification
against the owner's live Kavita is an owner step (see "Owner steps" below).

### D3 — Conflict notice names positions (`reading-progress`)

One title in conflict: name the kept and the discarded position (page or
percentage, matching how that title reports progress) in the notice text.
Several titles: state the count and add a "Show" action opening a list that
names both positions for each title. Both platforms, all four locales — no
new component, an extension of the existing conflict-notice view/composable
and its string catalogue entries. Spec impact: none (the main
`reading-progress` spec already asks for this; only code and strings were
missing).

### D4 — Chapter markers inside a publication (`comic-reader`)

Both marker kinds count: the ComicInfo `<Page Bookmark>` attribute (parsed
already by `ComicInfo.swift` / the Kotlin equivalent) and, on iOS only, the
PDF outline exposed by PDFKit (`PDFDocument.outlineRoot`) — Android has no
PDF outline API per ADR-0012, so Android reads ComicInfo only. Chapter
actions (`ReaderChapters.swift`, `ReaderMenuSheet.kt`) move within the
publication first and only open a neighbouring publication at the first or
last chapter. Spec impact: none.

### D5 — Double-tap from fit-to-width (`comic-reader`)

"Fit" means the chosen fit mode. The double-tap toggle measures against the
scale of that mode (`ZoomablePage.swift`, `PageZoom.kt`) rather than a fixed
fit-to-screen scale. Spec impact: none.

### D6 — Pinch zoom on a page turn (`comic-reader`)

"Zoom level" means the pinched scale. In fit-to-width, carry that scale to
the next page (`ZoomablePage.swift` state, `ReaderScreen.kt` /
`ReaderViewModel.kt` equivalent), which opens at its top in reading order
(top-right for right-to-left). Spec impact: none.

### D7 — End screen and automatic cleanup (`comic-reader`, `offline-downloads`)

The end screen offers "Remove download" when "remove downloads after
finishing" is off. When it is on, the end screen states that the download
goes when the reader closes and offers "Keep", which exempts this publication
from the sweep. The sweep itself (`FinishedDownloadSweep.swift` and its
Android equivalent) is unchanged — it still runs at reader close, next
launch, or library change, not the instant the book ends. The exemption is a
boolean the sweep already needs to read before acting; it is the same store
the end screen writes to on "Keep". Spec impact: delta on `comic-reader`
"Navigation within a publication" and `offline-downloads` "Storage
management" (written).

### D8 — Comic page bookmarks (`comic-reader`)

Bookmarks apply to every fixed-page publication (comic archives, PDF,
fixed-layout EPUB), through the same annotation store PDF marks already use.
A tap on a bookmark jumps to the page and leaves a return mark, matching the
existing PDF-mark return behaviour. Spec impact: none.

### D9 — Android sharpness on API 31/32

Below the OS-level sharpening API's floor, build a CPU fallback: an
unsharp-mask convolution over the decoded `Bitmap`, run off the main thread
(Kotlin coroutine on `Dispatchers.Default`), applied at the same point in
`PageAdjustments.kt` where the platform sharpening runs on API 33+. The
control stays available and produces the same visible result on API 31 and
32. Spec impact: none.

### D10 — Forward curl on the last page (`page-transitions`)

The curl on the last page reveals the end-of-publication screen beneath it,
as the next sheet, rather than lifting into empty space. A tap or a key past
the last page opens the end screen directly with the chosen transition. Both
platforms add `canTurnForward` to `CurlTurn.progress` (`CurledPages.swift`,
`CurledPages.kt` / `PageCurl.kt`) so the destination beneath the curl is the
end screen rather than `nil`. Spec impact: delta on `page-transitions` "The
curl" (written).

### D11 — Withholding Curl for a slow device (`page-transitions`)

Measure the first three curls in a session (frame-interval samples captured
during `The page follows the finger`). **Threshold: when the median of those
three frame intervals exceeds 1.5× the display's own refresh interval** (for
example, on a 60 Hz display, a median frame time above ~25 ms), persist a
per-device "cannot curl" flag (`ReaderModel.swift` / the Android
`ReaderViewModel` equivalent — see `ShelfMemoryTests.swift:137` for the
existing test scaffold for a per-device flag). Withhold Curl with the reason
stated once, and keep the reader's *stored* preference so a later app version
or a faster device can restore Curl without asking again. Spec impact: none
(the main spec already requires that Curl not be offered where it cannot be
honest; only the measurement was missing).

### D12 — Curved roll edge and shadow (`page-transitions`)

Replace the straight-line fold with a fold position that is a non-linear
function of `y` — a cone anchored at the corner, or an equivalent
radius-varies-with-height curve — in `PageRoll.swift` (SwiftUI/Core Animation
path) and in both curl shaders: `PageCurl.metal` (Metal Shading Language, iOS)
and the Android `RuntimeShader` in `PageCurl.kt` (AGSL, Android 13+/API 33+ —
the app's floor for the shader path is already API 33 per the existing
`canCurl` gate). Spec impact: none.

### D13 — Refused turn feedback (`page-transitions`)

Keep the haptic (`UIFeedbackGenerator` / Android `HapticFeedbackConstants` or
`VibrationEffect`) and add a bounded rubber-band offset that springs back, in
every non-scroll transition mode. When Reduce Motion is on, replace the
offset with a brief dim instead of a translation. Spec impact: none.

### D14 — Double-page spread curling as one surface (`page-transitions`)

Composite the spread into one texture per side before handing it to the curl:
one bitmap/`CGImage` covering both pages, built the same way the existing
double-page compositing for other transitions works, then let `isPairing`
include Curl in the pairing check (`ReaderNavigation.swift`,
`ReaderScreen.kt`). Spec impact: none.

### D15 — Light/dark theme pair (`reading-themes`, `settings-and-about`)

Add a stored light preset and a stored dark preset to `AppSettings` on both
platforms (Swift `Codable` struct field / Kotlin data class field backed by
the existing settings `DataStore`), defaulting to Paper and Quiet. Add two
pickers — a `Picker` (iOS) / `ExposedDropdownMenu` or radio list (Android
Material 3) — under the "Follow appearance" link toggle in Appearance
settings, in all four locales. `linkedPreset` (iOS) and the Android
equivalent resolve from this stored pair instead of a hardcoded map. Spec
impact: delta on `reading-themes` "Theme presets" and `settings-and-about`
"Appearance" (written; the latter carries `reader-theming-and-page-
transitions`'s in-flight Natural-theme delta as a superset — see
"Cross-change ordering" below).

### D16 — Original theme and publisher styles (`reading-themes`, `ebook-reader`)

Apply what the platform can honour under publisher styles: typeface, bold
weight and margins apply under Original, and margins become visible there
(Readium's EPUB navigator preferences — `fontFamily`, `fontWeight`/`bold`,
`pageMargins` — are documented as effective regardless of the
`publisherStyles` preference; **Assumed** until confirmed against the pinned
Readium release in `design.md` of `reader-theming-and-page-transitions` or
its `Package.swift`/`gradle.kts` version). Hyphenation cannot apply under
publisher styles (Readium exposes no hyphenation override there), so it moves
into the "unavailable under Original" notice. No control stays live while it
changes nothing. Spec impact: delta on `reading-themes` "Theme presets" and
`ebook-reader` "Reflowable rendering" (written; the latter is also a
superset — see below).

### D17 — iOS inline compact bar sentence skip (`read-aloud-and-reader-theming`)

The whole inline read-aloud row (`PlayerDock.swift`) opens the full player in
one tap; the full player already carries sentence skip and the way back to
the book, so no new control is added to the compact bar itself. Spec impact:
none.

### D18 — Opening a comic or PDF ends a running voice (`read-aloud-and-reader-theming`)

A comic or a PDF is a different publication for this purpose. Opening one
runs the same handover check the app already runs between two audiobooks
(`StoryArcAppActions.swift`, `EpubReadAloud.swift`): it displaces the voice,
writes its position, and shows the existing voice-stopped notice. Spec
impact: none.

### D19 — Sleep timer fades a synthesised voice (`audiobooks-and-playback`)

Fade by lowering each queued `AVSpeechUtterance`'s volume in steps across the
last 10 seconds of the timer, then stopping at the end of the current
sentence (`PlaybackSource.swift`). On Android, this arrives once read-aloud
joins the shared media3 player (see the separate "Android read-aloud does not
drive the shared player" task); until then there is no Android sleep timer
for read-aloud to fade. Spec impact: none.

### D20 — Licence inventory (`settings-and-about`)

List every shipped library with its licence text: iOS `SMBClient`, the eight
Readium transitive packages, `bcprov` (Bouncy Castle), `jsoup` (via Readium)
and `desugar_jdk_libs` (GPL-2.0 with the Classpath Exception) on Android.
Android replaces `jcifs-ng` with `smbj` (Apache-2.0, decision D26), which
removes the LGPL question `jcifs-ng` raised; list `smbj`'s own dependencies
too. Make the iOS decode (`Licences.swift`) tolerant of an entry it cannot
parse and show a stated message instead of silently emptying the section.
Spec impact: none (the main spec already requires a complete, accurate
inventory; only the entries and the decode were missing).

### D21 — EPUB readers take the cover accent (`native-experience`)

Match the comic readers: the EPUB end-of-book surface takes the cover-derived
accent (the existing accent-extraction path each platform's detail screen
already uses) on both platforms. The chrome drawn over the page stays
untinted — the iOS Liquid Glass rule and the Android fixed scrim, both
already in force for the comic readers. Spec impact: none.

### D22 — Android theme sheet on a large screen (`native-experience`)

At medium window-size class and wider (Jetpack `WindowSizeClass`/
`currentWindowAdaptiveInfo`), show level one of the theme surface as a
non-modal Material 3 surface: a `Popup` with Material elevation and shape,
anchored to the theme control, with the page visible beside it. Compact width
keeps `ModalBottomSheet`. Spec impact: none.

### D23 — Android EPUB WebView accessible name (`native-experience`)

Name the Readium navigator's `WebView` with the publication title, set where
`PublicationEgress.deny(view)` runs (`PublicationEgress.kt`), using
`View.setAccessibilityPaneTitle` (or an equivalent `contentDescription` that
does not shadow the page's own reachable content). Verify with the
accessibility-node tree that TalkBack still reads the page content, not just
the pane title. Spec impact: none.

### D24 — Android persistable hand-over grant (`local-library`)

When the sending app's intent carries
`FLAG_GRANT_PERSISTABLE_URI_PERMISSION`, call
`ContentResolver.takePersistableUriPermission` on it and list the file as a
remembered single publication — at most the twenty most recently opened —
the same rule iOS already applies to its security-scoped bookmarks
(`OpenedFile.kt`). Spec impact: delta on `local-library` "Opening a single
file" (written).

### D25 — Android local network permission (`network-share`)

Declare `ACCESS_LOCAL_NETWORK` in the manifest — **Assumed**: this is the
Android platform permission that gates local-subnet access starting with the
release the project's target SDK 37 tracks; confirm the exact API level
against the SDK the CI toolchain resolves before shipping, because Android's
local-network gating has moved across releases. Request it at the moment of
first need — opening SMB discovery, or the first connection to an SMB share,
an OPDS catalogue, or a Kavita server on the LAN — via
`ActivityResultContracts.RequestPermission`, with a rationale. On denial:
hide discovery, keep manual entry, tell the reader once (in the surface that
asked) how to grant it in system settings, and give a connection failure
blocked by the missing permission its own sentence, distinct from
host-unreachable. Spec impact: new requirement on `network-share` (written).

### D26 — SMB 3 encryption (`network-share`, `settings-and-about`)

Android: replace `jcifs-ng` with **smbj** (Apache-2.0), which negotiates SMB
3.x with encryption. iOS: first check whether a newer `SMBClient` release
negotiates SMB 3 with encryption; if not, extend the vendored client with SMB
3.0.2 and 3.1.1 dialect negotiation and AES-CCM/AES-GCM encryption — labelled
**Assumed** pending that check, because the currently vendored `SMBClient`
version is what ADR-0010 recorded as SMB 2-only. Report the negotiated state
per session through `SmbIdentity` and `SourceDiagnosis` on both platforms, and
draw the source-detail "encrypted" sentence from that reported state instead
of the current hardcoded constant. Record the client choice in a new ADR that
updates ADR-0010 and ADR-0016. Spec impact: none (the main `network-share`
spec's "Encrypted transport" scenario already requires this; only the client
capability was missing).

### D27 — `PageDecoder.isSpread` caller (`publication-formats`)

Call `PageDecoder.isSpread` at both `noteDecoded` call sites on each platform
so the 1.2 "materially wider" margin actually applies, rather than leaving
the function unreachable. Spec impact: none.

### D28 — Share rows catalogued from headers (`publication-formats`)

When a share row nears the viewport (`LazyColumn`/`LazyVGrid` `onAppear` /
Compose's equivalent visibility callback), index it by ranged read through
`PublicationIndexer.index(source:...)` and merge the detected format, page
count, cover path and streaming state into the row model on both platforms.
Spec impact: none.

### D29 — OPDS covers on the shelf (`opds-catalog`, `one-library-three-destinations`)

Fetch the cover image lazily, when the cell asks for it, through the
existing origin-bound HTTP client (the same one that carries certificate
pins), and cache it alongside local covers in the existing cover cache. An
unreachable catalogue draws the coverless well with the format symbol, grey,
matching every other offline row. Spec impact: none.

### D30 — One download queue per platform (`offline-downloads`)

One app-level queue (a Swift `actor` on iOS, a singleton guarded by a
`Mutex`/`kotlinx.coroutines.sync.Mutex` on Android) becomes the *only* writer
of the download store on its platform. Every download record carries its
source id; the queue resolves that source's credential and certificate pins
from the secure store at the moment the transfer starts, rather than a
catalogue page resolving and caching its own stale copy. The concurrency
bound moves from per-catalogue to global (a counting semaphore on the
queue). Spec impact: none (the main spec already implies one writer; the
code ran several).

### D31 — Thirteen wording rows (`localization`)

For each of the thirteen rows, take the wording each platform's own
guidelines use where they differ legitimately — Apple HIG terms on iOS,
Material Design terms on Android — and one shared wording where they do not.
Land every row in all four locales (en, fr, de, es) on both platforms. Spec
impact: none.

### D32 — Server list/shelf removal and deletion (`kavita-server`, `collections-and-reading-lists`)

Build both against Kavita's documented routes (read from its OpenAPI
document, same caveat as D2), through the existing Kavita write queue, with
the same confirmation dialog local shelves already use. Extend
`scripts/kavita-server.mjs`. Live verification against the owner's live
Kavita is an owner step (see "Owner steps" below).

### D33 — Curl honours fit, zoom and PDF marks at rest (`comic-reader`, `page-transitions`)

At rest, the curl mode draws the same adjusted, trimmed, fit-and-zoomed page
body — including PDF marks — that every other transition mode draws
(`ReaderPage.swift`'s normal draw path). The curl rasterises the page to a
texture only while a turn is actually in progress, handing that raster to the
Metal/AGSL shader. Spec impact: none.

### D34 — Fixed-layout EPUB background and brightness (`ebook-reader`)

Add the existing comic-reader matte swatches to the fixed-layout EPUB
reader's menu, stored per series through the existing
`remembering(_:for:.fixedLayout)` path, and add the existing reader-local
screen-brightness control. Both are reused components; no new persistence
shape. Spec impact: none.

### D35 — Axis slider reset gesture (`reading-themes`)

Both gestures reset an axis: the existing long press and a new double tap,
through the same reset path, each announced to VoiceOver
(`.accessibilityAnnouncement`) and TalkBack
(`AccessibilityManager`/live-region announcement). Add
`onDoubleTap`/`TapGesture(count: 2)` alongside the existing long-press
detector. Spec impact: none.

### LL — local-library "unauthorized" vs "unreachable" (`local-library`)

The code already marks a folder whose grant is gone as `unreachable` on both
platforms, on purpose — offline is a normal state (grey, not red), one of
this project's non-negotiables. Keep that state name; do not rename it to
`unauthorized` to match the old spec wording. Add what `unauthorized` would
have given the reader and `unreachable` was missing: name the specific lost
access in the explanation, and keep the existing single re-pick action. Spec
impact: delta on `local-library` "Folder libraries" (written) — the scenario
now says `unreachable`, not `unauthorized`.

## Cross-change ordering

Two of this change's deltas MODIFY a requirement that `reader-theming-and-
page-transitions` (an in-flight, unarchived change) also MODIFIES:
`settings-and-about` "Appearance" (D15) and `ebook-reader` "Reflowable
rendering" (D16). Per `AGENTS.md` §5, each of this change's blocks is written
as a superset of `reader-theming-and-page-transitions`'s block plus this
change's own addition, and the required sync order —
`reader-theming-and-page-transitions` before `close-the-audited-gaps` — is
recorded in `.delta-drops.json` under `collisions`, so `pnpm delta:drop`
enforces it rather than relying on memory. `pnpm delta:drop` passes clean
against both blocks as written.

## Owner steps

These are built as far as code reaches; the last step is the owner's, and no
task in `tasks.md` ticks itself on that step:

- **Home-screen widgets** (`native-experience`): the WidgetKit extension, the
  Glance widget and the shared snapshot are built in code. iOS App Group
  provisioning needs the owner's Apple development team.
- **CarPlay** (`audiobooks-and-playback`): the scene and templates are built
  in code. The CarPlay audio entitlement needs the owner's Apple development
  team.
- **Kavita write routes** (D2, D32): built against the documented API and the
  mock server. The owner confirms behaviour against their live Kavita
  instance.
- **Curl over reflowable text** (`page-transitions` 4.3b): needs Readium's
  resource-boundary timing measured on a simulator and an emulator before the
  approach is built, because the technique depends on how fast Readium can
  hand over a rasterisable resource boundary — this is a measurement task,
  not an owner-only step, but it gates the build task that follows it.

## Risks / Trade-offs

- **[Risk]** D16's claim that Readium's EPUB navigator preferences apply
  typeface, weight and margins under `publisherStyles: true` is Assumed, not
  verified against the pinned Readium version. → **Mitigation**: the task for
  D16 starts with a spike against the actual pinned Readium release; if the
  navigator does not honour these overrides under publisher styles, the
  fallback is exactly what the pre-decision code did (inert, in the notice),
  and the spec delta's wording ("StoryArc's typeface, weight, margins and
  font size apply over them") is what would need `/opsx:update`, not a silent
  divergence.
- **[Risk]** D25's exact Android API level for `ACCESS_LOCAL_NETWORK` and its
  request flow is Assumed. → **Mitigation**: verify against the CI-resolved
  Android SDK before the manifest change lands; the permission-denied path
  (hide discovery, keep manual entry) already exists and is the safe fallback
  if the declaration turns out to need a different gate.
- **[Risk]** D26's iOS SMB 3 encryption depends on whether a newer
  `SMBClient` release exists with SMB 3 support; if not, the vendored-client
  extension is a large, security-sensitive piece of work. → **Mitigation**:
  the check runs first, as its own task, before any vendored-client work is
  scheduled; the new ADR records whichever path is taken.
- **[Risk]** D30's single download queue changes where credentials and pins
  are resolved for every kind of transfer (local folder, SMB, OPDS, Kavita).
  A missed call site could silently drop authentication for one download
  kind. → **Mitigation**: `tasks.md` orders the queue consolidation (task
  1.1) before the per-kind fixes that depend on it (OPDS keying, Kavita
  chapter downloads, streamed-read credentials), and each of those later
  tasks re-asserts its own credential path against the new single queue.
- **[Trade-off]** D9's CPU sharpening fallback on Android API 31/32 costs
  battery and a frame or two of latency the OS-level path does not. Accepted
  because the alternative is an unavailable control on two still-supported
  API levels, and the owner's rule favours the fuller feature.

## The field report of 2026-09-28

The owner tested the v0.1.1 closed-testing build on an Android phone and reported seven
problems. Four are defects inside existing requirements, and three need the two new
requirements in this change's `sources` and `library-browsing` deltas.

| Report | Decision |
| --- | --- |
| Rotation freezes the app on the library page | A defect. Reproduce on an emulator, find the blocking work, fix it. Check the iOS rotation path. |
| A shelf keeps the previous destination selected, and back is needed to return to search | A shelf and every library section opened from the navigation belong to the Library destination. The navigation marks Library, and the shelf goes on the Library stack. |
| The rail's menu button is at the far left in landscape | Material 3 puts the menu button at the top of the navigation rail, on the leading edge. Keep it when it matches; fix it when it does not. |
| A comic from a Kavita reading list spins for ever | A defect. It opens as the same chapter opened from its series does, or it states why it cannot. |
| The library may not hold all of a Kavita server | It does not: the first read takes the 60 newest series and never continues (SMB: 200 publications). The app now keeps reading in the background until it holds all of each source, and states its progress. |
| Kavita collections and reading lists on Home have no cover | Draw the server's own cover (Image/collection-cover, Image/readinglist-cover), then the first members' covers, then the coverless well. |
| The finished mark is hard to see; long press should offer actions everywhere | A finished badge in each platform's own form (Material 3 badge on Android, an SF Symbol in the system material on iOS). One action builder per platform, offered by a long press with a DropdownMenu on Android and by .contextMenu on iOS, on every surface that draws a publication. |

