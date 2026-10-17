# macOS wave 3 — sources, downloads, diagnostic, storage and shelves

Taken 2026-10-17 at the head of `lane/macos-wave3` from the ad-hoc build of
`apps/desktop-macos` (macOS 27.0.1, Xcode 27.1) over `packages/test-fixtures/comics`, copied
into the app's container as its one library folder. The screens are the ones wave 3 added or
changed in `Tests/MacCatalogue.swift`. As for wave 2, the catalogue empties the progress
store, puts `natural-sort.cbz` at page 5 of 12 and marks `image-pages.cbz` finished on
15 January 2026. For wave 3 it also clears finished downloads and makes two shelves: the
collection *Weekend* and the reading list *Crossover*, each holding `image-pages`,
`natural-sort` and `zip64` (the list holds them in reverse). Tasks 3.10 to 3.15a of
`desktop-clients`. The conformance walk that reads these frames is
[`desktop-conformance-macos-wave3.md`](../../../../../delivery/desktop-conformance-macos-wave3.md).

Every screen has four frames: light and dark, each at the default text size and at the
app's own **Largest** text size (Settings > Appearance > Text Size).

| Frame | What it shows |
| --- | --- |
| `home-<variant>.png` | Home with Keep reading, then the Collections shelf (*Weekend*, 3 books) and the Reading Lists shelf, which states how far through the list the reader is. The sidebar's Shelves group lists both shelves, pinned shelves first and then by name, with the **+** menu that makes a new collection or list. |
| `shelf-collection-<variant>.png` | The *Weekend* collection's page: its members as covers, in title order. |
| `shelf-list-<variant>.png` | The *Crossover* reading list's page: numbered entries in the reader's order, each with how much of it is read. |
| `downloads-<variant>.png` | Downloads with one finished catalogue download (*Fine Print*, 1.3 MB). |
| `settings-sources-<variant>.png` | Preferences > Sources: the server sources (none in the catalogue), *Add Source*, and the sync place with its sentence about start and quit. |
| `source-share-<variant>.png` | The *Add a Network Share* sheet: the Bonjour list (nothing announces itself on the capture Mac), the host and share fields, and the optional sign-in. |
| `source-catalogue-<variant>.png` | The *Add a Catalogue* sheet. |
| `source-kavita-<variant>.png` | The *Add a Kavita Server* sheet. |
| `settings-downloads-<variant>.png` | Preferences > Downloads: the metered rule with the connection as it is now, and Storage with each store's size and its own *Clear*. The sizes are pinned by the catalogue. |
| `settings-privacy-<variant>.png` | Preferences > Privacy with *Export Diagnostic…*. |
| `diagnostic-<variant>.png` | The diagnostic sheet over Privacy: the full text before the save panel. It is built from fixed inputs, with the system version left out. |

`<variant>` is `light`, `dark`, `light-largest` or `dark-largest`.

## How they were taken

`screencapture` has no Screen Recording grant in an agent session, so the frames come from
`Wave3CaptureTests` inside the app, which asks the window server for the app's own windows,
as the wave 2 frames do:

```bash
cd apps/desktop-macos
TEST_RUNNER_STORYARC_CAPTURE=1 xcodebuild test -project StoryArcMac.xcodeproj -scheme StoryArc \
  -destination 'platform=macOS' -only-testing:StoryArcMacTests/WindowWalks/Wave3CaptureTests
# frames: ~/Library/Containers/com.mecedric.storyarc/Data/tmp/captures/wave3/
pnpm frames:shrink <copied folder>
```

Every frame came back marked `window-server` with the app active (`method.txt` in the
capture folder).

## Limits, read with the frames

- **The covers are flat colour.** The fixtures are generated archives whose pages are
  single-colour images.
- **The skipped-files notice is dismissed.** The frames show the *What couldn't be opened*
  link, as the snapshot references do, not the wave 2 banner.
- **No live server rows.** The sheets are drawn empty. The walks that add a share, a
  catalogue and a Kavita server against the mock servers do not leave rows behind, so
  Sources shows none. The undo bar of a bulk mark and the bulk download question are not
  drawn here.
- **Fixed sizes.** The library window is held at 1100 × 720 points for each frame, as for
  wave 2.
