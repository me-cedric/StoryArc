# Android frames for the re-scope lane, 2026-10-10

Device: emulator `storyarc-ci` (API 35, google_apis, arm64), started headless with `-memory 2048`.
Display 1080x2400 at 420 dpi. Debug build `com.mecedric.storyarc.debug` from this branch.
All frames use the default text size. A frame with no `-dark` twin is light only, and the table says so.
Frames are shrunk to 540x1200 with `pnpm frames:shrink`.

Fixtures: `node scripts/corpus.mjs <dir>` pushed into
`/sdcard/Android/data/com.mecedric.storyarc.debug/files/`. OPDS mocks on ports 4444 and 4447.
`node scripts/seed-android-sources.mjs --ports 4444,4447` (it needs `adb` on PATH).
The animation scales were set to 0 for the walks and put back to 1 after.

Snapshot references (no emulator) were added in the same lane. They are in
`apps/android/feature/library/src/test/snapshots/`, light and dark:
`01b-home-finish-and-next`, `01c-home-finish-alone`, `01d-home-source-away`,
`01e-home-after-finish`, `01f-home-pinned-shelves` and `05c-cover-chooser-candidates`.

## Frames and what they prove

| Frame | Task | What it proves |
| --- | --- | --- |
| `home-hero-and-shelf-{light,dark}.png` | one-library 2.1, publication-detail 2.3 | Home with the Keep reading hero (Resume, "2 pages left") and the Recently added shelf. First frame of both paths. |
| `path1-shelf-card-opens-page-{light,dark}.png` | publication-detail 2.3 | Path 1. A tap on the shelf card "Fine Print" opens its page. |
| `path2-hero-opens-reader-page3-light.png` | publication-detail 2.3 | Path 2. The hero opens the reader with no page between, at page 3 of 5, the stored page. Light only. See defect 1: the dark frame was not taken. |
| `detail-increase-contrast-{light,dark}.png` | publication-detail 1.4 | The page of "Fine Print" with `contrast_level` 1.0. The hero is the plain `surfaceSunken` ground. The control is `path1-shelf-card-opens-page-*`: the same page at the standard level, with the orange cover wash. |
| `browse-home-*`, `browse-library-list-*`, `browse-downloads-*`, `browse-search-two-sources-*` | publication-detail 3.4 | Two OPDS sources are registered. Home, the Library in list layout and Downloads name no library on any row. Search "slow" labels each row ("From Attic Catalogue", "From Loft Catalogue"), the one exception. Light and dark. |
| `shelf-menu-pin-to-home-*.png`, `shelf-menu-unpin-from-home-*.png` | one-library 2.1 | The shelf menu: "Pin to Home" above Rename and Delete, and "Unpin from Home" for the pinned shelf. Delete is last. Light and dark. |
| `home-pinned-collection-*.png` | one-library 2.1 | Home with the collection "Harbour stories" pinned: a section of that name with its two titles. Light and dark. No reading list was pinned here; `01f-home-pinned-shelves` snapshot draws a collection and a reading list in their own orders. |
| `home-after-unpin-light.png` | one-library 2.1 | After "Unpin from Home" the section is gone from Home. `shelf-menu-pin-to-home-light.png` was taken after the unpin and shows the collection still on the Shelves screen. |
| `detail-state3-source-not-answering-*.png` | publication-detail 2.2 | State 3. The Attic mock is stopped. The page says "It is not on this device, and the library it lives in is not answering. It will be fetched when that library is back." and the line "From Attic Catalogue, not answering right now". The earlier defect 6 does not occur. Light and dark. |
| `fr-detail-source-not-answering-*.png` | one-vocabulary 4.6, close-the-audited-gaps 15.10 and 26.3 | The same state in French: "Elle n'est pas sur cet appareil, et la bibliothèque où elle se trouve ne répond pas..." and "De Attic Catalogue, sans réponse pour le moment". Light and dark. |
| `fr-detail-not-downloaded-*.png` | one-vocabulary 4.6, close-the-audited-gaps 15.10 and 26.3 | A server title that is not downloaded, source answering, in French: "La télécharger" and "De Attic Catalogue, pas sur cet appareil". Light and dark. |
| `detail-copy-travelling-no-progress-defect-light.png` | publication-detail 6.5 frame 2 | **Does not prove the frame.** "Slow Transfer" 8 seconds after the metered confirmation was accepted. The page shows Read and no "Downloading" label and no fraction. Defect 2. |

Reused, not retaken:

- `../android-epub-end-card-2026-10-08/` proves close-the-audited-gaps 9.7 on Android, light and dark, with the no-cover control.
- `../frames-android-2026-10-09/pane-seq-*.png` prove the window resize sequence of one-library 4.3 and publication-detail 4.2.
- `../frames-android-2026-10-09/skipped-list-es*`, `open-in-refused-fr*` and `reader-cannot-open-fr*` prove one-vocabulary 1.7, 2.4 and 3.4 on Android.
- `../frames-android-2026-10-09/pd-copy-1-absent*`, `pd-copy-3-landed*`, `pd-copy-4-shade*` prove publication-detail 6.5 frames 1, 3 and 4.
- `../wave4-android-2026-10-09/` and `../wave6-android-2026-10-09/` prove close-the-audited-gaps 24.4 on Android.

## Owed

- **publication-detail 6.5 frame 2** (the page while a copy travels). Defect 2 is open.
- **path 2 in dark** (publication-detail 2.3). The reader opened page 1 in all three dark tries. Defect 1.
- **one-library 4.2 foldable at half-open.** The lane has one AVD, a phone with no hinge and no posture sensor.
- **cover-for-every-publication 4.3.** Chrome shows its first-run screen. A person must dismiss it.
- **French state d (source removed, no copy), the French gone state, and the French second place** (4.6, 15.10, 26.3). Not staged.
- **reader-theming 4.3b backward curl across a chapter end.** Not tried: wave 4 and wave 5 could not turn a page on the emulator.
- **read-aloud 3.2.** The speech engine on the emulator crashes, so the voice never moves.
- **reader-theming 7.6.** TalkBack needs a person.

## Defects found (not fixed)

1. **Resume on the Home hero opens a PDF at page 1 and the progress is lost.** "Field Notes" (PDF, 5 pages) read to page 3. Home then shows "2 pages left". A tap on the hero opened page 1 in 6 of 9 tries, and afterwards the hero was gone from Home. The same tap opened page 3 in 3 of 9 tries. The failing tries came after Home was left through a publication page, after a cold start, or in dark mode.2. **The page does not draw the copy while it travels.** Same as wave 5 defect 3. After "Download" with the metered confirmation, the page shows Read with no "Downloading" label and no fraction.
3. **"Next in series" wraps one letter per line on the Home hero.** `01b-home-finish-and-next-light.png` draws "Finish" and "Next in series" side by side on a card of about 205 dp. The second button is a narrow capsule about 235 dp high. The same code runs on a phone. The accessibility checks of the snapshot do not catch it. The reference records the fault as it is. Re-record it after the fix.
4. The Library draws "Cellar Catalogue hasn't been read yet" as a line above the tab bar. It names a library on a browse surface. It is a source notice and not a row label. Listed so the owner can decide for 3.4.

## Repeat

```bash
export PATH=$HOME/Library/Android/sdk/platform-tools:$PATH ANDROID_SERIAL=emulator-5554
node scripts/corpus.mjs /tmp/sa-corpus
node scripts/opds-server.mjs /tmp/sa-corpus --port 4444   # and 4447
node scripts/seed-android-sources.mjs --ports 4444,4447
pnpm capture:android "Search > one title two sources" --out f.png [--dark]
adb shell settings put secure contrast_level 1.0         # then 0.0 after
adb shell cmd locale set-app-locales com.mecedric.storyarc.debug --locales fr   # and en after
pnpm snap:android                                         # the snapshot references
```
