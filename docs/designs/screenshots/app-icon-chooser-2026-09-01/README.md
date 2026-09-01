# The app icon a reader chooses — 2026-09-01

`brand-identity-and-app-icons` §6. The icon is the deliverable, so a screenshot of the chooser
is not sufficient on its own: every face is photographed where the *system* draws it.

## Every face, where a reader sees it (§6.1)

| Face | iOS home screen | Android launcher |
| --- | --- | --- |
| Ink (default) | `ios-home-ink.png` | `android-launcher-ink.png` |
| Paper | `ios-home-paper.png` | `android-launcher-paper.png` |
| Bloom | `ios-home-bloom.png` | `android-launcher-bloom.png` |
| Arc | `ios-home-arc.png` | `android-launcher-arc.png` |
| Mono | `ios-home-mono.png` | `android-launcher-mono.png` |

Both walks drive the app's own chooser rather than setting anything behind its back. On iOS
`AppIconCaptureTests` taps the row, answers the system alert iOS puts up — the app does not
suppress it, and that it appears at all is a fact these captures happen to prove — waits for
the chooser to mark the face, and only then presses Home. Waiting for the *mark* is what makes
the photograph trustworthy: the mark moves inside `setAlternateIconName`'s completion handler,
so a mark means the platform agreed.

The Android shots are the launcher's own All Apps list, filtered to StoryArc so one icon is
unambiguous. Every one was taken after asserting that **exactly one** launcher component was
enabled, printed in the run log.

**The Android launcher masks to a circle on this device.** The plate and the mark are the
app's; the outline is the launcher's, and it differs per device.

## The chooser (§6.2)

| | Default text | Largest text |
| --- | --- | --- |
| iOS, light | `ios-app-icon-chooser.png` | `ios-app-icon-chooser-ax5.png` |
| iOS, dark | `ios-app-icon-chooser-dark.png` | `ios-app-icon-chooser-ax5-dark.png` |
| Android, light | `android-app-icon-chooser.png` | `android-app-icon-chooser-ax2.png` |
| Android, dark | `android-app-icon-chooser-dark.png` | `android-app-icon-chooser-ax2-dark.png` |

**The iOS tiles are blank in these captures, and that is the state of the code rather than a
bad screenshot.** An `.appiconset` compiles into `Assets.car` as an *Icon Image*, and an icon
asset is not fetchable by name: `Image("AppIcon-Paper")` and `UIImage(named: "AppIcon-Paper")`
both answer nothing, which draws an empty tile and is not an error anywhere.
`ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS` emits no loose file either, and listing the
generator's own PNG a second time as a resource makes XcodeGen write a flattened path that does
not build. `xcrun assetutil --info` on the built catalogue is where that was settled.

The fix is in `scripts/brand-mark.swift`, which already writes those bytes: an `.imageset`
beside each `.appiconset`, named `AppIconTile-<Face>` — the name `AppIconChoice.tileResourceName`
declares and `AppIconChoiceTests` asserts. That file belongs to the mark rather than to this
change's territory, so it is reported rather than edited.

Android's tiles are the components' own launcher icons, read through `PackageManager` with
`MATCH_DISABLED_COMPONENTS`, so a face whose manifest entry is wrong looks wrong in the chooser
rather than only on the home screen.

**The first Android capture found a real defect.** Paper's plate is `#F8F6F4` and the settings
surface is a warm off-white too, so its tile had no boundary at all and read as a plateless
mark beside four plated ones — the one face a reader could not see. Both platforms' tiles carry
a hairline now; the `-dark` and `-ax2` shots are after that fix.

At the largest text size the names stay readable in full, the tiles stay the size a launcher
draws them, and the list scrolls — the tile is fixed rather than scaled precisely so the name
beside it keeps the width it needs.

## Themed icons (§6.3) — not captured

**A gap, not an exception.** Turning Android's themed icons on could not be automated on this
emulator inside the time available. Writing `themed_icons` into the Pixel launcher's own
preferences read back `true` and changed nothing — every icon in the drawer stayed full colour —
and `android.intent.action.SET_WALLPAPER` opens a disambiguation dialog rather than the
Wallpaper &amp; style screen the toggle lives on.

What *is* asserted without a device: `AppIconManifestTest` checks that every one of the five
adaptive icons points `<monochrome>` at `@drawable/ic_launcher_monochrome`, the flat art, and
never at the gradient foreground. That is the whole of task 4.2's reasoning — a gradient tinted
flat loses the mark's internal divisions — but it is not a photograph of it.

## How these were taken

```bash
# iOS — one test per face, because `--only <Class>` alone is prefixed with `ScreenshotTests/`
# and matches nothing while xcodebuild still exits 0.
pnpm capture:ios --out <dir> --only AppIconCaptureTests/testCaptureHomeAInk
pnpm capture:ios --out <dir> --only AppIconCaptureTests/testCaptureAppIconChooser --appearance dark
```

Android was driven by a scratch script over `scripts/android-routes.mjs`'s navigator: the
chooser lives inside the existing *Settings > Appearance* route, and the thing photographed is
the launcher, which no route map covers.

**Both platforms' captures were taken on a device the run verified.** An install can report
`Success` and be replaced minutes later by another agent's build on a shared emulator — that
happened here, and the walk drove an app whose chooser simply was not there. Every Android run
prints `lastUpdateTime` before it starts.
