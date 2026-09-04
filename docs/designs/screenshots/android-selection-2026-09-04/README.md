# Android selection mode, as a contextual top app bar — 2026-09-04

The Android half of `named-failures-and-quieter-chrome` §3b.7. The chrome it photographs
shipped on 2026-09-03 **with no captures at all**, because both devices were sweeping when it
landed; these are the ones it owed.

Every frame is `storyarc-j6` (a 1080 × 2400 phone AVD at 420 dpi, `-gpu host`), taken with
`scripts/capture-android.mjs` against the routes named below. All appearance settings are at
their defaults — the app had written no settings store on this device — so **dynamic colour
is on**, which is the condition the sweep's non-`nodynamic` frames were taken in.

## The pairing: these are the after

The seven `android-library-selection-*` frames in
[`../android-sweep-2026-09-02/`](../android-sweep-2026-09-02/README.md#library--selection-mode)
are the **before**. They photograph the full-bleed bottom slab — a `Surface` of
`surfaceRaised` across the foot of the shelf holding a count, three `IconButton`s and a
*Done* — and that README labels itself as superseded. `BulkActionBar.kt` is deleted.

| State | Before, in `android-sweep-2026-09-02/` | After, here |
| --- | --- | --- |
| Nothing selected, light | `android-library-selection-none.png` | `android-library-selection-none.png` |
| Nothing selected, dark | `android-library-selection-none-dark.png` | `android-library-selection-none-dark.png` |
| Nothing selected, `font_scale 2.0` | `android-library-selection-none-scale2.png` | `android-library-selection-none-scale2.png` |
| Two selected, light | `android-library-selection-two.png` | `android-library-selection-two.png` |
| Two selected, dark | `android-library-selection-two-dark.png` | `android-library-selection-two-dark.png` |
| Two selected, `font_scale 2.0` | — none was taken | `android-library-selection-two-scale2.png` |
| The overflow open | — the slab had none | `android-library-selection-overflow.png` · `-dark` |

The names match on both sides on purpose, so each pair is a before and an after of the same
walk on the same AVD. Two of the before frames have no counterpart here:
`-two-nodynamic` and `-two-nodynamic-dark` compared dynamic colour on against off, and this
pass did not touch that switch.

## What the frames show

**The bar is at the top, and the navigation bar is untouched.** In all eight frames the foot
of the window still holds Home / Library / Downloads / Search, for the whole of the mode. That
is the deliberate divergence from iOS, which hides its tab bar and floats a glass capsule
where the tab bar was: `LibrarySelectionTopBar.kt`'s header records it, ADR-0001 licenses it,
and on Android the foot of the window is the navigation bar's territory.

**The shape is the Material 3 contextual top app bar.** Close at the start in the accent,
`0 selected` / `2 selected` from `R.plurals.library_selected` as the title, a download arrow
and a filled check as actions, an overflow after them. It is drawn on `surfaceRaised` rather
than on the canvas the library's own bar sits on, so the mode change is visible as a change of
bar rather than of buttons.

**`Add to…` is named in words.** `android-library-selection-overflow.png` is the one frame
that proves the claim: the overflow holds a single row reading **Add to…**, with `PlaylistAdd`
as a leading icon rather than as the whole affordance. That was the point — the action opens a
chooser, and `PlaylistAdd` alone is the sort of glyph the 2026-09-01 design review objected to.
The route exists (`Library > selection overflow`) so the wording stays checkable.

**At `font_scale 2.0` the count and the actions do not compete.**
`android-library-selection-two-scale2.png` and `-none-scale2.png` are the stress case the
brief asked for, and the bar holds: the title grows, does not ellipsize, and the close plus
the three actions all stay on one row at full size. The chip row below it wraps to two lines
and the shelf drops to two columns, both of which are the shelf's own behaviour and unchanged
by this work. In the `two-scale2` frame the walk had to scroll the shelf to reach *Foreign
Codec* at that text size, so only one of the two ticks is on screen — the bar's own
`2 selected` is what carries the count there.

**The `2 couldn't be opened` notice above the chip row is not part of this chrome.** It is the
state of this AVD's shelf (the corpus ships two deliberately broken files) and it appears in
every frame here and in the before set alike.

## Two things the frames said that the code's header did not — and one the retake added

**These frames were retaken on 2026-09-04 after both defects below were fixed**, and after a
third the fix surfaced. The originals photographed the bar as it shipped; what is on disk now
is the bar as it stands. Everything the first pass measured is kept here, because the numbers
are how the defects were found and the retake is what proves they are gone.

### The actions were inert when nothing was picked, and nothing showed it — fixed

`LibrarySelectionTopBar.kt` says the three "go inert together when nothing is picked, and are
drawn rather than hidden". The first half is true — `enabled = false` reaches every one of
them — and the second half is where it goes wrong. Cropping the action region out of the two
light frames at the same offset gives **byte-identical PNGs**:

```
sips -c 110 380 --cropOffset 165 690 android-library-selection-none.png --out a.png
sips -c 110 380 --cropOffset 165 690 android-library-selection-two.png  --out b.png
# 50458955b45925652088fd7d0291652c91435fe91fc89b365a7d93cb9d12c57d, both
```

`IconButton` dims a disabled child through `LocalContentColor`, and each `Icon` in the bar
passes `tint = palette.accent` explicitly, which overrides it. So at `0 selected` a reader
sees three controls drawn exactly as live as at `2 selected`, and two of them do nothing. The
close affordance is genuinely live throughout and looks the same as the three that are not.

**Fixed, and the retake measures it.** The accent now arrives as the `IconButton`'s
`contentColor` through `IconButtonDefaults.iconButtonColors` instead of the `Icon`'s `tint`, so
Material derives the disabled treatment from the colour it was given rather than from an alpha
of ours. The same region that was byte-identical now differs by **1 182 of 17 141 pixels** in
light and **1 184** in dark, worst channel delta 110 and 136. The close affordance keeps its
explicit tint, and only it: the way out of a mode is never disabled, so nothing there can be
taken away. `BulkSelectionChromeTest.a disabled action is drawn differently from a live one`
rasterises the node in Robolectric and fails if the two states ever match again.

### The mark-as-read glyph was the picked-cover mark — moved

Found by reading these frames against the reworded requirement rather than by any test. The bar
drew mark-as-read as `Icons.Filled.CheckCircle` tinted `palette.accent`; `PickMark` draws every
**picked cover** in the same frame as `Icons.Filled.CheckCircle` tinted `palette.accent`. Same
vector, same tint, one symbol asked to mean *picked* and *mark as read* at once, four rows
apart — and `android-library-selection-two.png` shows both at once.

`native-experience`'s *Every action names itself* refuses exactly that: a mark another control
in the same frame already uses is not established here, whatever it means elsewhere. iOS had
answered the weaker version of the same collision — `checkmark.circle` is the visual *union* of
the picked disc and the unpicked ring rather than the picked mark itself — by keeping the word
beside the glyph wherever a word fits. A top app bar's action slot has no room for a word at
any width, so this platform's answer is the overflow, where the name is drawn in full. The bar
is now close · count · download · overflow, and `android-library-selection-overflow.png` shows
*Mark as read* and *Add to…* as two named rows.

### The accent is still the purple the sweep flagged

The close, the download arrow, the check, the overflow dots and the cover ticks are the same
Material-baseline purple that
[§4 of the sweep](../android-sweep-2026-09-02/README.md) recorded against the old bar — the
finding survived the rebuild, on the same controls. That section reached its conclusion by
comparing a dynamic-on frame against a dynamic-off one; this pass captured only dynamic-on, so
it re-confirms the colour but not the "same in both schemes" half.

## Reproducing

```bash
pnpm capture:android "Library > selection none"     --out none.png
pnpm capture:android "Library > selection two"      --out two.png --font-scale 2.0
pnpm capture:android "Library > selection overflow" --out overflow.png --dark
```

The build in these frames was verified rather than assumed: `app-debug.apk` hashed
`295e11b5eacc04af883e1caae3954d47f62f2e74954035f8a17b115387dd54c4`, and
`sha256sum` on the device's `base.apk` answered the same before the first shutter and after
the last, at the same `codePath`. It did not match on arrival — another worktree's build was
installed — which is why the check runs at both ends.
