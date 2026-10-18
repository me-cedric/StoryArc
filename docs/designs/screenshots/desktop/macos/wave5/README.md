# macOS wave 5 — the chrome accent, the click zones and the curl

Taken 2026-10-18 at the head of `claude/lane-macos-wave56-7be24f` from the ad-hoc build of
`apps/desktop-macos` (macOS 27.0.1, Xcode 27.1, MacBook Pro M1 Pro). Task 5.11 of
`desktop-clients`, with the curl of task 5.1. The screens are those of `Tests/MacCatalogue.swift`
over the fixture library, light and dark, at the default text size.

| Frame | What it shows |
| --- | --- |
| `home-accent-brand-<scheme>.png` | Home with the accent left at its default, the StoryArc colour: the sidebar's selection and icons, the progress bar. |
| `home-accent-system-<scheme>.png` | Home with Appearance > Accent set to System. |
| `settings-appearance-accent-<choice>-<scheme>.png` | The Appearance tab with the choice in force. |
| `reader-zones-on-<scheme>.png` | `natural-sort.cbz` in a reader with the edge click zones on, the default. |
| `settings-reading-zones-on-<scheme>.png` | The Reading tab with *Turn pages by clicking the edges* on, its footer stating the thirds, and *Page turn* offering Curl with no sentence saying it is missing. |
| `reader-curl-mid-turn.png` | The same reader in Curl, a key turn caught about half way: the phone's shader rolling page 3 over page 4, the back of the sheet darkened and its shadow on the page beneath. |

`<scheme>` is `light` or `dark`; `<choice>` is `brand` or `system`.

## How they were taken

As for waves 2 to 4, from inside the app, which asks the window server for its own windows:

```bash
cd apps/desktop-macos
TEST_RUNNER_STORYARC_CAPTURE=1 xcodebuild test -project StoryArcMac.xcodeproj -scheme StoryArc \
  -destination 'platform=macOS' -only-testing:StoryArcMacTests/WindowWalks/Wave5CaptureTests \
  -only-testing:StoryArcMacTests/WindowWalks/CurlWalkTests
# frames: ~/Library/Containers/com.mecedric.storyarc/Data/tmp/captures/wave5/
pnpm frames:shrink <copied folder>
```

`method.txt` in the capture folder names the method of each frame: all twelve came from the
window server.

## Limits, read with the frames

- **The two accents draw alike on this Mac.** Its system accent is Multicolor, the default, and
  under Multicolor macOS gives every app its own accent, which is the StoryArc colour the app
  declares. So the *system* frames differ from the *brand* ones only in the picker's words.
  `ChromeAccentTests` holds the rule with a fake system accent (green): brand by default, the
  system's once chosen, a later change of the system's reaching the chrome. A Mac set to a named
  accent in System Settings > Appearance shows the difference; that frame is the owner's.
- **The click zones are not drawn.** They are the left and right thirds of the page, as on a
  phone, and a reader sees them only by clicking; the frame shows the reader with the setting on.
  `PointerReadingTests` holds that the zones are on when nothing is stored, a third each, off
  when turned off, and mirrored right-to-left; `PageKeyMapperTests` holds the keys (task 2.12).
- **The curl frame is taken while the turn runs**, so the copy from the window server costs that
  turn some frames; the frame times in `docs/delivery/desktop-budgets-macos.md` come from runs
  that take no frame.
- **The fixture pages are flat colour**, so the curl shows its geometry and shading, not a
  drawn page.
