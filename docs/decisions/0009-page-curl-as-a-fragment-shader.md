---
status: accepted
date: 2026-08-25
deciders: Cédric Meyer
---

# ADR-0009 — The page curl is a fragment shader over two decoded pages

Records the outcome of the Phase 0 curl spikes in the
[`reader-theming-and-page-transitions`](../openspec/changes/reader-theming-and-page-transitions/proposal.md)
change (tasks 0.3 and 0.4). Task 0.6 asked for this ADR by name, on the grounds
that "the curl decision is exactly the kind of thing that gets re-litigated in
six months without one".

## Context and problem statement

[`page-transitions`](../openspec/specs/page-transitions/spec.md) exists as a
capability for one reason, stated in its own purpose: "the curl is the one
interaction in StoryArc that no library provides. Readium exposes every
typographic preference and no transition preference at all."

So the curl is ours, on both platforms, and it has to be finger-tracked,
interruptible, lit along its leading edge, shadow-casting, and mirrored for
right-to-left. The spec also forbids shipping it badly: "the app never ships a
curl that stutters in preference to a slide that does not."

[ADR-0005](0005-format-and-rendering-libraries.md) left the implementation path
open and marked it *needs a spike*. `design.md` proposed rastering each page to a
texture and deforming a mesh in a **Metal vertex shader** on iOS, and expressing
"the same cylindrical projection" as an **AGSL `RuntimeShader`** on Android at
API 33+.

Both spikes were run. Both came back **go**, and both contradicted part of the
proposal. That is what this ADR records.

## Decision drivers

- The spec's own escape hatch: Curl must be absent, not degraded, where a device
  cannot honour it.
- [ADR-0003](0003-platform-floors.md) keeps the Android floor at API 31, and
  `RuntimeShader` arrives at 33.
- [ADR-0001](0001-independent-native-cores.md) means two implementations, so the
  cheaper each one is, the smaller the divergence risk.
- `comic-reader` states that a curl over a comic page "uses the already-decoded
  page directly rather than a re-raster".

## Considered options

| Option | Why not |
| --- | --- |
| **`UIPageViewController.TransitionStyle.pageCurl`** (iOS) | Interactive and free, and it wants to own the view-controller hierarchy — which the Readium navigator already occupies. `design.md` assumed it unsuitable; nothing in the spike changed that. iOS-only besides, so Android would still need its own. |
| **A deformed mesh in a vertex shader** | The path `design.md` proposed. Needs geometry to deform and a raster to texture it with. The spike found the geometry contributes nothing (below), so the mesh is machinery around a projection that a fragment shader expresses directly. |
| **`oleksandrbalan/pagecurl`'s `graphicsLayer` approach** (Android) | Kept as the geometry reference it was always intended to be. As an implementation it is Compose-only, so iOS would diverge, and it predates `RuntimeShader`. |
| **One fragment shader over two page textures, per platform** | **Chosen.** One function, no mesh, no raster for comics, and the same three regions expressed twice. |

## Decision Outcome

**A fragment shader on both platforms, over the two decoded pages, with no mesh
and no rastering for comic content.**

### It is a fold, and the crease draws nothing

The proposal said "cylindrical projection". A cylinder was authored first, and
then abandoned for a reason worth keeping:

Seen straight down — which is how a reader sees a page — a folded sheet shows
exactly two things and hides a third. The part not yet reached lies flat. The
turned part lies face-down on top of it. And the crease is *edge-on*: every point
on the cylinder projects to a position that the flat turned sheet, being higher,
also covers. **The crease contributes no pixels.**

That is why every convincing 2D page curl *shades* its crease rather than
projecting it, and why this one does. Modelling a cylinder here would be
modelling geometry that draws nothing, then drawing the crease anyway.

The three regions, in the direction of the turn:

| Region | What is drawn |
| --- | --- |
| Beyond the turned sheet's edge | the page as it lies, not yet reached |
| Under the sheet | the same page mirrored about the crease, dimmed to 55% — its back |
| Past the crease | the page beneath, darkest against the crease |

The dimming is not decoration. A mirrored image at full brightness reads as a
reflection; paper is not transparent.

**The regions are easy to get backwards, and the mistake is loud.** The turned
sheet lies *left* of the crease and the reveal is *right* of it: the material that
used to lie ahead of the crease is what folds back over the page behind it.
Inverting it renders the *next* page at rest, which is how the first attempt
announced itself.

### One projection, expressed twice

`design.md` asked for the projection to be "authored once conceptually and
expressed twice rather than solved twice". The two files are line-for-line
counterparts, down to the three constants — crease width 0.06 of the page, shadow
reach 0.05, back face 0.55.

| | iOS | Android |
| --- | --- | --- |
| Language | Metal, `[[stitchable]]` | AGSL |
| Entry point | `PageCurl.metal` → `ShaderLibrary.bundle(.module)` | `PageCurl.kt` → `RuntimeShader` |
| Applied as | `Rectangle().fill(shader)` | `ShaderBrush` on a `Canvas` |
| Two pages in | two `texture2d<half>` arguments | two `BitmapShader` inputs |
| Outside the page | `address::clamp_to_edge` plus a bounds test | `TileMode.DECAL` |

Right-to-left is a coordinate flip inside the shader, not a second shader: the
crease originates from the opposite edge and the gesture mirrors with it, which is
all the spec asks for.

### A brush, not a `RenderEffect`

On Android the obvious API is
`RenderEffect.createRuntimeShaderEffect`, and it is the wrong shape: it binds the
**view's own content** to one input. A turn needs two pages at once. Two
`BitmapShader`s into one `RuntimeShader`, drawn as a brush, is `comic-reader`'s
sentence about using the decoded page directly, in code.

### Capability, not quality, is the gate

`page-transitions` has two reasons a device may not get Curl: it lacks the
capability, or it cannot hold the refresh rate. Only the first is answerable at
build time.

- **Android: API 33.** `RuntimeShader` arrives there and ADR-0003 keeps the floor
  at 31. Below it Curl is absent from the picker with a sentence naming the
  requirement rather than an API level, Slide is the default, and a stored Curl
  preference is left intact. Three unit tests hold exactly that.
- **iOS: no gate.** SwiftUI's shader API predates the iOS 26 floor, so there is no
  capability to test.
- **Frame rate: measured where it runs, or not at all.** A frame rate measured on
  an emulator or a simulator running on a Mac's GPU is not a frame rate. The
  shader is a handful of texture reads and one exponential per pixel, so a
  frame-rate check with no device known to fail it would be speculative
  complexity. `canCurl` is a constructor parameter on both readers precisely so
  that a check can be added the day a device needs one.

**So tasks 0.3 and 0.4 close without the number they asked for**, and this is the
honest reason rather than an omission. Task 0.4b — the API 31 gate end to end —
needs an API 31 device and is still open.

### Interruption is a property of the animation primitive

"A new drag while a curl is still settling takes over from the current position
without the page snapping" is not extra code. It is `Animatable.stop()` on
Android and a re-targeted `withAnimation` on iOS: both leave the value where it
stands rather than queueing behind the running spring. Choosing the primitive
correctly is the whole implementation.

One trap found here: driving an `Animatable` from a drag means launching a
coroutine per move event, and those had not run by the time the finger lifted —
so the release decision read a progress of zero and sprang **every** turn back.
The reached fraction is kept in the gesture loop, where the decision is made.

## Consequences

**Gained**

- No mesh, no render pipeline, no raster for comics. The whole curl is one
  function per platform plus a gesture.
- Comics pay nothing: the page is already decoded and the shader samples it.
- The escape hatch the spec required is real and already exercised — Android below
  API 33 is its first consumer, which is the point of having written it before it
  was needed.

**Accepted costs**

- **Building the iOS app now needs the Metal toolchain**, which is not part of a
  default Xcode install: `xcodebuild -downloadComponent MetalToolchain`, about
  690 MB. It is a separate download rather than something a package can declare,
  so it is recorded in [the iOS README](../../apps/ios/README.md). A fresh clone
  fails with `cannot execute tool 'metal'` until it is installed.
- Two shaders to keep in step. The mitigation is that they are short and their
  constants are named the same in both.
- **The iOS curl is unverified visually.** The simulator accepts no injected
  input, so the reader cannot be reached to drag a page. What is verified is that
  `pageCurl` is a stitchable symbol in the feature bundle's `default.metallib`
  with the expected arguments. Tasks 7.4 and 7.5 need a device or a person.

**Follow-up**

- **4.3b — rastering for reflowable content** is the remaining hard part. Comics
  avoid it; an EPUB page is live web content and the deforming surface must be a
  texture, so `page-transitions`' "the turning page is a faithful raster of the
  page it replaces" still has to be built.

  **No longer untouched, and the ADR said it was.** Fast fade over reflowable text
  now ships on both platforms, which is the one-raster half. And 4.3b has since
  established, from Readium's own source, that the *second* raster needs **no second
  offscreen navigator** — the neighbouring resources are already loaded and laid out
  (`PaginationView.loadedViews` at the navigator's default preload counts), and
  within one resource the next page is a CSS column in the same web view. What is
  unsettled is no longer the source of the texture but the frame cost of reaching
  it: `PaginationView.slideToView` sleeps 100 ms on an unanimated resource-boundary
  move, by construction. 4.3b in the change's `tasks.md` carries the measurement and
  the two routes past it.
- The frame-rate check, if a device ever justifies one.

## Revisit when

- A platform ships an interactive page-curl transition that can host an arbitrary
  view hierarchy, which would make both shaders deletable.
- A device turns up where the shader misses the refresh rate — which is the
  evidence that would justify the runtime check this ADR declined to build.
- The two shaders drift. That would be evidence that expressing one projection
  twice was the wrong trade, and the argument in
  [ADR-0001](0001-independent-native-cores.md) would need re-examining for this
  layer specifically.

## Links

- Spec: [`page-transitions`](../openspec/specs/page-transitions/spec.md), and
  `comic-reader`'s "Curl over image pages" scenario.
- Change: [`reader-theming-and-page-transitions`](../openspec/changes/reader-theming-and-page-transitions/tasks.md)
  tasks 0.3, 0.4, 0.6 and 4.3.
- Code: `apps/ios/Packages/StoryArcKit/Sources/ReaderFeature/PageCurl.metal`,
  `apps/android/feature/reader/src/main/kotlin/app/storyarc/feature/reader/PageCurl.kt`.
- Related decisions: resolves the transition row
  [ADR-0005](0005-format-and-rendering-libraries.md) left open; constrained by
  [ADR-0003](0003-platform-floors.md)'s API 31 floor; a second instance of
  [ADR-0001](0001-independent-native-cores.md)'s "write it twice" trade.
- Geometry reference: `oleksandrbalan/pagecurl`.
