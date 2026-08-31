# The third batch of 2026-08-31, before

The navigation shell as it stood before `quiet-shell-and-search` section 1 — search as a
role on iOS, and absent from Android's bar entirely.

## How these were taken

Both trees were at `bc3d3a49` with **no working changes**. The iOS shot in particular was
retaken from a stashed-clean tree: a first attempt ran `pnpm capture:ios` concurrently with
the edits, and `xcodebuild` compiles files as it reaches them, so there was no way to know
whether what it photographed was the old shell or the new one. A "before" that might be an
"after" is worth nothing, so it was discarded and taken again.

```bash
pnpm capture:ios --out docs/designs/screenshots/before-2026-08-31c --only testCaptureHome
pnpm capture:android Home --out …/android-home-default-light.png
pnpm capture:android Home --out …/android-home-default-dark.png  --dark
pnpm capture:android Home --out …/android-home-scale2-light.png  --font-scale 2.0
```

Devices: `StoryArc-iPhone17Pro` (11DFC984), and the `storyarc-j6` emulator started with
`-gpu host`.

## What each one shows

| Shot | What is in it |
| --- | --- |
| `ios-home.png` | Three destinations in the floating capsule, and **search as a separate circular button on the trailing edge, outside it**. That is `Tab(role: .search)`: the button is not a fourth tab, and tapping it does not lead anywhere — it expands in place into a text field that takes the rest of the bar with it. |
| `android-home-default-light.png` | Three destinations, edge-to-edge. No search anywhere in the navigation: it was a field belonging to the library screen. |
| `android-home-default-dark.png` | The same three, dark. |
| `android-home-scale2-light.png` | The same three at the largest accessibility text size — the control on which the four-destination arithmetic had to still work. |

## The caveat worth stating

`pnpm capture:android` drives whatever APK is installed; it does not build or install one.
The first "after" attempt in this batch photographed the previous build and showed three
destinations, which reads exactly like a change that did not work. Run `pnpm gradle
installDebug` before capturing, and check that the picture disagrees with the "before"
before believing either of them.

## Not captured, and why

`pnpm capture:ios` with no `--only` fails on `ScreenshotTests.testCaptureLibrary`, and the
script discards every screenshot from a failed run rather than lifting the ones that
succeeded. The failure is **pre-existing** — it reproduces on an unmodified tree at
`bc3d3a49` — and it is why this batch is one iOS shot rather than the usual set. It is not
diagnosed here.
