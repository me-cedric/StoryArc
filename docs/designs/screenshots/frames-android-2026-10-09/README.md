# Android frames, wave 5 - 2026-10-09

Device: emulator `storyarc-store` (API 35, google_apis, arm64), started headless with `-memory 2048`.
Display 1440x3200 at 560 dpi, which is 411x914 dp. Debug build `com.mecedric.storyarc.debug` from
the head of `main` (`51f314d4c`). The APK was built at 07:26 on 2026-10-09 and no product file of
`apps/android` changed after it.

All frames use the default text size. Dark frames end in `-dark`. A frame with no `-dark` twin is
light only, and the table says so.

Fixtures: `node scripts/corpus.mjs /tmp/sa-corpus`, pushed into
`/sdcard/Android/data/com.mecedric.storyarc.debug/files/`. OPDS mocks on ports 4444, 4447, 4448
(4448 stopped for the "not answering" state). `scripts/seed-android-sources.mjs --ports 4444,4448`.
`scripts/smb-server.sh --encrypted /tmp/sa-corpus` on port 4446.
A helper outside the repository (`/tmp/sa-f/tools/d.mjs`) drove the walks. It calls
`navigator().perform()` of `scripts/android-routes.mjs`, so each step is a route step.
No file outside `docs/designs/screenshots/` changed.

## Frames and what they prove

| Frame | Task | What it proves |
| --- | --- | --- |
| `pd-state-1-downloaded*.png` | publication-detail 2.2 | State 1, a local copy ("Field Notes", PDF): one primary, Read. |
| `pd-state-2-cached-remote-overflow*.png` | publication-detail 2.2 | State 2, a remote copy not on the device. The overflow is open. It holds no second download entry, so Download stays the one primary. |
| `pd-state-3-source-stopped*.png` | publication-detail 2.2 | State 3 as far as it can be reached: the Loft catalogue is stopped (the Settings list says "Not answering") and the page of "Broken Transfer" from Loft shows no button and the sentence "This cannot be opened until it is on this device (2.0 kB)." **It does not show the NEEDS_SOURCE text.** The provenance line says "From Loft Catalogue, not on this device" and not "not answering right now". See defect 6. |
| `pd-bare-page-coverless-411x914*.png` | publication-detail 2.4 | A bare page at 411x914 dp: "Foreign Codec", no series, no year, no description, no cover. The well is drawn with the format symbol. |
| `pane-seq-1-expanded.png`, `pane-seq-2-narrow.png`, `pane-seq-3-widened.png` | publication-detail 4.2 | Light, default text. 1: window 2560x1600 at 320 dpi (800 dp tall, 1280 dp wide), "Field Notes" shown in the pane. 2: `wm size 1600x2560` (500 dp wide), the page fills the window and the bottom bar replaces the rail. 3: `wm size 2560x1600` again, the same publication is still shown. `wm size` and `wm density` were reset after. |
| `pd-copy-1-absent*.png` | publication-detail 6.5 frame 1 | Absent publication, library answering: "Download it" is primary, with the sentence "This cannot be opened until it is on this device." |
| `pd-copy-2-travelling*.png` | publication-detail 6.5 frame 2 | **Does not prove the frame.** Taken while the 45-second copy runs (status bar shows the download icon). The page shows Read and no fraction and no "Downloading" label. See defect 3. |
| `pd-copy-3-landed*.png` | publication-detail 6.5 frame 3 | After landing: Read is primary and the provenance line says "On this device, readable with no network", plus "Also in Attic Catalogue". |
| `pd-copy-4-shade*.png` | publication-detail 6.5 frame 4 | The notification shade after the app left, while the copy travels: "Downloading 1 title" with a progress bar. This is the foreground-service notification. |
| `cover-chooser-no-candidate*.png` | cover-for-every-publication 3.6 | The "Choose a cover" sheet, reached from "Find a cover" with the lookup on. It shows the no-candidate sentence (no picture candidates). Partial, see below. |
| `cover-menu-lookup-on*.png` | cover-for-every-publication 3.6 | The cover menu with the lookup on: "Choose a picture", "Find a cover", "Find a cover on the web". |
| `cover-web-handoff-chrome-first-run.png` | cover-for-every-publication 4.3 | "Find a cover on the web" leaves the app. Chrome opened on its first-run screen. Not the image search, see owed. |
| `skipped-list-es*.png`, `skipped-list-en*.png` | one-vocabulary 1.7 (Android) | The "Lo que no se pudo abrir" sheet in Spanish with the two skipped files, and the English control. |
| `open-in-refused-fr*.png`, `open-in-refused-en*.png` | one-vocabulary 2.4 (Android) | `am start -a VIEW -t text/plain` with a `.txt` file. The alert "Impossible d'ouvrir ce fichier" in French, and the English control. |
| `reader-cannot-open-fr*.png`, `reader-cannot-open-en*.png` | one-vocabulary 3.4 | A truncated PDF ("Truncated Notes", 700 bytes of "Field Notes.pdf") in the reader: "Ce titre n'a pas pu être ouvert." and "This title could not be opened." |
| `fr-detail-e-also-in*.png` | one-vocabulary 4.6, state (e) | French page with a copy on the device and a second place: "Sur cet appareil, lisible sans réseau" and "Aussi dans Attic Catalogue". |
| `comic-adjustments-fr*.png` | one-vocabulary 4.6 | The comic matte menu in French: "Couleur derrière une page de BD", nine swatches. |
| `comic-adjustments*.png` | close-the-audited-gaps 24.4 | The comic adjustment sheet, English: three sliders and the matte swatches. |
| `epub-themes-swatches*.png` | close-the-audited-gaps 24.4 | The EPUB theme sheet, expanded: six theme swatches with Paper checked. |
| `epub-selection-menu*.png` | close-the-audited-gaps 24.4 | The EPUB selection menu: Yellow, Green, Blue, Pink, Purple. The dark frame has the same page: the reader keeps its own cream theme. |
| `pdf-selection-colours.png` | close-the-audited-gaps 23.1 | PDF word selection ("Field") and its five highlight colours. Light only. |
| `pdf-highlight*.png` | close-the-audited-gaps 23.1 | The word highlighted yellow on the PDF page, light and dark. |
| `pdf-spread-highlight*.png` | close-the-audited-gaps 23.1 | Two-page spread (landscape 2560x1600): page 1 keeps its highlight, page 2 beside it. |
| `rail-wide-window*.png` | close-the-audited-gaps 24.6 | A wide window (2560x1600 at 320 dp): the navigation rail, the library list with the A to Z rail, and the empty detail pane. 12 letters are drawn. |
| `smb-share-detail-encrypted*.png` | close-the-audited-gaps 23.3 (Android) | Share detail against the `smb encrypt = required` share on port 4446: "StoryArc reads this share over SMB 3.1.1. The connection is encrypted." |

Also reused, not retaken: `../android-epub-end-card-2026-10-08/` holds the EPUB end card frames (9.7).
The coverless well and chosen-cover frames of `../cover-for-every-publication/` now come from
`../wave4-android-2026-10-09/` (see that README).

## Owed

- **publication-detail 4.2 foldable half-open frame.** The lane may use one AVD, `storyarc-store`, which is a phone. It has no hinge and no posture sensor. A Pixel Fold AVD is needed. The window-size sequence above is a different task.
- **Readers-proof frames 1 and 2** (backward curl across a chapter end after a resume, and the forward chapter-end fold at a high frame rate). "The Long Field" opened on one copy at the start of Chapter 4 with the system animation scales set to 1.0 and Curl chosen. `record-android-turn.mjs back` (one tap on the leading third), a horizontal swipe and a vertical swipe turned nothing in three tries over 20 minutes. The recording is 27 identical frames. Wave 4 saw the same. See defect 2.
- **cover-for-every-publication 3.6, the chooser with pictures.** The lookup hosts are https only and the emulator got no candidate, so only the empty sheet is framed. A recording transport in a capture test is needed.
- **cover-for-every-publication 4.3, the web hand-off.** Chrome showed its first-run sign-in screen, and a person has to dismiss it. Nothing here enters an account.
- **one-vocabulary 4.6, French states (d) and the gone state.** (d) is a publication whose source was removed with no copy, and the gone state needs a stale route. Neither could be staged in the time.
- **EPUB selection menu, PDF and the other reader frames in dark** are light only where the table says "Light only".
- **iOS share frame on port 4445 (23.3).** iOS belongs to the frames-ios lane.

## Defects found (not fixed)

1. The Library on a 411x914 dp phone with a 2-item skipped notice and a "showing what was here" line leaves few rows above the fold; not new, listed for the record.
2. EPUB reader, Curl chosen, "The Long Field": no tap and no swipe turns the page. Text of Chapter 4 runs under the bottom pill. Same as wave 4.
3. Publication page while a copy travels: no progress block (label "Downloading" and a bar) shows, although the status bar and the shade say a download runs and the code at `PublicationDetailScreen.kt:544` draws one from `transfer`. The copy came from the Search result row for a title held by two catalogues.
4. After a "Remove download" the file is gone but the Library still says "On this device" for the title until the next scan.
6. The page of a title from a stopped catalogue does not take the NEEDS_SOURCE state: the Settings list says "Not answering" and the page keeps the NOT_DOWNLOADED provenance and the refusal sentence, never `detail_needs_source` (wave 4 saw the same lag for French state c).
5. Cover menu with the lookup on is cut at the right screen edge (same as wave 4 defect 2).

## Repeat

```bash
export PATH=$HOME/Library/Android/sdk/platform-tools:$PATH ANDROID_SERIAL=emulator-5554
node scripts/corpus.mjs /tmp/sa-corpus
node scripts/opds-server.mjs /tmp/sa-corpus --port 4444   # and 4447 or 4448
node scripts/seed-android-sources.mjs --ports 4444,4448
pnpm capture:android "Search > one title two sources" --out f.png [--dark]
pnpm capture:android "Settings > Privacy > cover lookup on" --out f.png [--dark]
pnpm capture:android "Sources > share detail encrypted" --out f.png    # scripts/smb-server.sh --encrypted /tmp/sa-corpus
adb shell cmd locale set-app-locales com.mecedric.storyarc.debug --locales fr    # and es, en
adb shell wm size 2560x1600; adb shell wm density 320    # wide window; reset both after
```
