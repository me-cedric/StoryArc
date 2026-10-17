# macOS wave 2 — library, reader and preferences

Taken 2026-10-17 from the ad-hoc build of `apps/desktop-macos` (macOS 27.0.1, Xcode 27.1)
over `packages/test-fixtures/comics`, copied into the app's container as its one library
folder, with one reading position written for `natural-sort.cbz` (page 5 of 12) so Home has
a Keep reading shelf. Tasks 2.9 to 2.23e of `desktop-clients`; the conformance walk that
reads these frames is [`desktop-conformance-macos-wave2.md`](../../../../../delivery/desktop-conformance-macos-wave2.md).

Every screen in four frames: light and dark, each at the default text size and at the
app's own **Largest** text size (Settings > Appearance > Text Size), which on a Mac stands
in for the system's largest text size that macOS does not have.

| Frame | What it shows |
| --- | --- |
| `home-<variant>.png` | The library window on Home: Keep reading with the one book in progress, its progress rail and percentage. No Up next shelf: no fixture series has a finished issue, so the shelf is absent, as `home-screen` asks of an empty shelf. |
| `library-grid-<variant>.png` | Library, as a grid, in title order, under the notice that two publications could not be opened (`refused.cb7` and `password-protected.cbz`), with *Show* and its close mark. |
| `library-list-<variant>.png` | Library, as a list: cover, title, series line and format, percent read at the end. |
| `search-<variant>.png` | The toolbar search with "sort" typed: the field stays in the toolbar and the results take the content column. |
| `detail-<variant>.png` | The publication page of `natural-sort`: the cover wash, the one primary action (*Continue at Page 5 of 12*), the borderless More menu, and the line naming the folder. |
| `reader-<variant>.png` | The reader window on page 5, with the chrome up: the page layout and zoom menus at the top, the counter and the page slider at the foot, both on glass. |
| `settings-appearance-<variant>.png` | Preferences, Appearance: appearance, accent (StoryArc or System) and text size. |
| `settings-reading-<variant>.png` | Preferences, Reading: the edge click zones (on), the cover alone (on), and the page turn, which says the curl is a later version. |

`<variant>` is `light`, `dark`, `light-largest` or `dark-largest`.

## How they were taken

`screencapture` has no Screen Recording grant in an agent session, as in wave 1, so the
frames come from `Wave2CaptureTests` inside the app, which asks the window server for the
app's own windows:

```bash
cd apps/desktop-macos
TEST_RUNNER_STORYARC_CAPTURE=1 xcodebuild test -project StoryArcMac.xcodeproj -scheme StoryArc \
  -destination 'platform=macOS' -only-testing:StoryArcMacTests/WindowWalks/Wave2CaptureTests
# frames: ~/Library/Containers/com.mecedric.storyarc/Data/tmp/captures/wave2/
pnpm frames:shrink <copied folder>
```

Every frame came back marked `window-server` with the app active, so these are the pixels
the display shows, sidebar and glass included, and the windows are drawn active, unlike
wave 1's.

## Limits, read with the frames

- **The covers are flat colour.** The fixtures are generated archives whose pages are
  single-colour images (`packages/test-fixtures/README.md`); a real cover has artwork. The
  cover wash on the detail page is therefore one hue. `no-pages.cbz` shows the coverless
  well with its format.
- **Fixed sizes.** The library window is held at 1100 × 720 points and the reader at
  980 × 820 for each frame, with resizing switched off for that frame, because a tiling
  window manager (Amethyst) fills the screen with every resizable window on the owner's Mac.
- **Dark is the app's appearance** (`NSApplication.appearance`), not the system's, which
  was left alone. The same applies to the accent: the frames show the StoryArc accent; the
  System choice follows the system accent live, and changing the system accent is a system
  setting this session does not touch.
- **The sidebar is the StoryArc accent because this Mac's system accent is Multicolor**, the
  default. A sidebar draws in the app's global accent only then; a reader who picked a
  system accent colour sees that colour there, as in every Mac app.
- **The picker values in Preferences keep the system's size** at Largest: a menu-style
  picker draws its value with the control's own font. The labels, the footers and every
  window's content scale.
- **Increase Contrast and Reduce Transparency are not here**, as in wave 1.
