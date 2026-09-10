## Context

See proposal.md — Why. ADR-0009 is the document this change argues with, and it
is worth being exact about which part.

ADR-0009 decides three things. Two of them stand and are what make this change
small: the curl is **one fragment shader over two decoded page textures**, with
no mesh and no re-raster for comics, expressed twice — `PageCurl.kt` as an AGSL
`RuntimeShader` and `PageCurl.metal` as a Metal fragment function, line-for-line
counterparts down to three shared constants (crease 0.06 of the page width,
shadow reach 0.05, back face 0.55).

The third is superseded here: *"It is a fold, and the crease draws nothing."*

That claim is true of a crease with **zero radius**, which is what was authored.
It is false of a roll. With a bend radius `r`, the sheet leaves the page, curves
over, and comes back down: the band it occupies in projection is about `πr/2`
wide, the leading edge lands `2r/π` short of where a zero-radius fold would put
it, and the silhouette across that band is a curve rather than a line. Those are
pixels, and they are the pixels a reader recognises as paper. The ADR's own
reasoning is not wrong; it answered "does a crease draw anything" and the answer
for a crease is no. This change asks a different question.

What exists today, and is the starting point:

- `CurledPages` (`feature/reader/CurledPages.kt:43`) takes `page` — the sheet
  being turned away — and `beneath` — "the page underneath it, or null at the
  last page". `ReaderScreen.kt:873` passes `paging.current` and
  `paging.current + 1`, and `onTurned` advances by one.
- `CurlTurn.progress` (`CurledPages.kt:213`) is
  `(base + forward(travel) / width).coerceIn(0f, 1f)`. The clamp at zero is the
  whole of why a backwards drag does nothing.
- `progress` is an `Animatable`, which is what makes an interrupted settle
  resumable; the header of that file explains it and the behaviour is asserted
  by `CurlTurnTest`.

## Goals / Non-Goals

**Goals:**

- One projection, still expressed twice. The two shader files stay
  counterparts; a divergence between them is a defect, not a platform detail.
- The roll's radius is one constant beside the existing three, so the look is
  tunable without touching the projection.
- Backwards costs no second shader. The same function draws it with the
  textures swapped and the direction inverted.

**Non-Goals:**

- Design-level: no vertex mesh, no `RenderEffect`, no page-curl library. If the
  fragment shader cannot hold 120 Hz with the roll, that is a finding to report,
  not a licence to add geometry — see Risks.
- No lighting model beyond the existing lit edge and cast shadow. A specular
  highlight travelling along the roll is not in scope.

## Decisions

**The roll is a signed-distance bend, not a projected cylinder.** In turn-space
the fold sits at `f = width * (1 - progress)`. Today the sheet's own edge is at
`2f - width`. With a radius `r` the shader instead treats the strip
`[f - πr/2, f]` as the curved band: within it, the texture coordinate is
remapped by the arc position `asin`/`cos` of the bend rather than by the mirror,
the back-face dimming ramps with the surface normal's dot product against the
viewer, and the silhouette is the curve where the normal turns away. Outside the
strip, the two flat regions are exactly what ADR-0009 already draws — the sheet
lying face-down, and the page beneath in shadow. The alternative, a full
cylindrical projection with a ray march, buys a rim highlight and costs a loop
in a fragment shader that must finish inside 8.3 ms.

**The radius is a fraction of the page width, and it shrinks as the turn
completes.** A magazine sheet bends tightest when it is nearly flat on either
side and most openly in the middle of the turn; a constant radius reads as a
tube sliding across. `r = R_MAX * sin(π * progress)` is one line and gives that
shape. `R_MAX` joins `CREASE`, `SHADOW` and `BACK` as a shared constant in both
files.

**Backwards is the same shader with the textures exchanged.** A backwards turn
is a forward turn of the *previous* page, seen from the other side: bind
`page = previous`, `beneath = current`, invert `direction`, and run progress
from 0 to 1 as the finger moves the other way. This is why the change does not
need a second projection. `CurledPages` gains a `previous: Bitmap?` parameter
and `onTurnedBack: () -> Unit`; `ReaderScreen.kt:873` supplies
`modelIndex(paging.current - 1)` and turns to `paging.current - 1`.

**`CurlTurn.progress` stops clamping at zero and gains a direction.** The value
becomes signed — negative is a backwards turn — and the caller picks which
texture set to bind from its sign. The clamp becomes `-1f..1f`. The first and
last page are handled by the caller: with no previous bitmap the negative range
is clamped to zero, which is the *Turning back from the first page* scenario and
is the same guard `beneath == null` already gives the last page.

**Platform APIs, verified present in the tree.** Android: `RuntimeShader`
(`android.graphics`, API 33+, already gated by the `TIRAMISU` check at
`CurledPages.kt`), two `BitmapShader` inputs, drawn as a brush — unchanged, plus
one more uniform and one more input shader. iOS: `ShaderLibrary.bundle(.module)`
over `PageCurl.metal`, as ADR-0009 records. No new dependency on either
platform. The AGSL and MSL texts stay translations of each other.

**Accessibility.** The curl is a visual affordance over a page turn that is
already reachable by tap and by keyboard — `ReaderScreen` binds both — and this
change adds a *gesture*, not a new way to reach a page. The backwards turn must
therefore also exist as the tap and key it already is, and the test for it
asserts the page changed, not that a finger moved. Reduce-motion is the case to
watch: a reader who has asked for less motion should get the mode picker's
existing fade rather than a richer animation, and this change must not make the
roll reachable where the fold was not.

## Risks / Trade-offs

- **The roll costs more per pixel than the fold, and the spec's floor is the
  display's refresh rate.** → `FrameProbe` and `FrameTicker` already instrument
  a turn and are armed by `adb`; the tasks measure before and after on the
  OnePlus 7T Pro at 90 Hz and on the slowest simulator device, and the change
  does not land if a turn drops frames. The fallback is a smaller `R_MAX`, then
  the fold.
- **A third page texture at full resolution.** Binding `previous` as well as
  `page` and `beneath` holds one more decoded bitmap for the life of the
  gesture. → The reader's page cache already holds neighbours for the slide
  mode; the shader binds what the cache has rather than decoding its own.
- **Two shader texts drifting apart.** The roll maths is longer than the fold's,
  so the counterpart discipline is under more strain. → The tasks require one
  test per platform asserting the same sampled pixels at the same progress, so
  a divergence fails rather than being noticed later by eye.
- **The mirror region is easy to get backwards, and ADR-0009 says so loudly.**
  Adding a curved band next to it does not make that easier. → The existing
  wrong-side symptom (the page beneath drawn at rest) is kept as an explicit
  test case.

## Migration Plan

None at runtime — no stored preference changes meaning, and a reader who chose
Curl keeps it. ADR-0009 is amended rather than replaced: its fold section is
marked superseded, with a pointer to this change and one sentence saying that
the argument holds for a crease and not for a bend of finite radius.
