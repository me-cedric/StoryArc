# Wave 6, Android frames and emulator proofs - 2026-10-09

Device: emulator `storyarc-ci` (1080x2400 at 420 dpi, API 35), headless, `-memory 2048`. Debug build `com.mecedric.storyarc.debug` built at the head of branch `wave-6`. All frames use the default text size. Dark frames end in `-dark`. A frame with no dark twin is light only.

Fixtures: `node scripts/corpus.mjs <dir>` and `node scripts/corpus.mjs <dir> --count 60` (filler comics for a full library), plus `fixture.epub`, `With Cover Long.m4b` (two minutes, built from `with-cover.m4b`) and `Long Walk.m4b` (a copy with the title changed). All pushed to `/sdcard/Android/data/com.mecedric.storyarc.debug/files/`. Kavita mock on 5000. Writable encrypted Samba share on 4449 (`scripts/smb-server.sh --writable --encrypted`, share `Sync`).

## Frames

| Frame | Task | What it proves |
| --- | --- | --- |
| `android-library-landscape-rest.png` | close-the-audited-gaps 25.2 | Phone landscape (914 x 411 dp), strip whole: title, chips and status line above the shelf. The A to Z rail draws 5 letters. |
| `android-library-landscape.png`, `-dark.png` | 25.2 | Same screen after one swipe up: the strip has scrolled away with the shelf. The rail draws 14 letters (before the fix: one letter, node 48 x 40 dp). |
| `android-cover-menu-chosen.png`, `-dark.png` | 25.3 (1) | Title page of a chosen cover ("Sea Room"), edit button tapped. The menu stays inside the window. Its right edge is 41 px from the screen edge (about 16 dp). The rounded corner is whole. |
| `android-kavita-title-needs-download-dark.png`, `android-kavita-title-needs-download.png` | 25.3 (2) | Kavita title not on the device ("Quiet Machines", light: "fixture"). "This cannot be opened until it is on this device." is legible on the wash, dark and light. |
| `android-player-bar-playing*.png`, `android-player-bar-paused*.png` | 25.3 (3), 25.7 | Compact player bar, light and dark, playing (pause mark) and paused (play triangle). The play triangle is white on the dark bar. The same frames show the Home card "Resume" button: white label on the violet accent. |
| `android-audiobook-continue-listening*.png` | 25.7 | Title page of an audiobook with progress. "Continue listening" is dark text on the pale accent, light and dark. |
| `android-epub-resume-0.45-light.png` | reader-theming 7.9 | `fixture.epub`, light, default size. The store held fraction 0.45 (page 3 starts at paragraph 24) and the element "Chapter 1, paragraph 12". The reader opened on the page that starts with paragraph 12. The element wins over the fraction. |
| `android-sync-conflict-one-title.png`, `-dark.png` | library-sync 5.4 | "Read in two places": `"fixture" moved on both this device and the library it came from - 90% was kept, not 25%.` with "Take the other" and "Keep the furthest". |
| `android-sync-conflict-several-titles.png`, `-dark.png` | 5.4 | Same notice for two titles: "2 titles moved on both ..." with "Keep the furthest", "Show" and "Take the other". |
| `android-sources-other-device.png` | 5.8 | Your libraries, light. "Silent NAS" and "127.0.0.1/Sync" carry "Added on another device". The 127.0.0.1 row adds "Its address names that device, so this device does not try it." |
| `android-sync-source-answered.png` | 5.7 | Your libraries after a sync, light: the sync share row "10.0.2.2/Sync" reads "Available - 0 titles", not Connecting. |

`smoke-android-a11y-player.txt` is the output of `node scripts/smoke-android.mjs --a11y Player` (see below).

## Emulator proofs

### 25.4 (Android half), `node scripts/smoke-android.mjs --a11y Player`

`node scripts/a11y-scan.mjs --self-test` prints `self-test passed`. The walk prints:

```
10/14 routes walked and survived
4 could not be reached -- the route map may be stale,
or this device has no publication in the state the route needs:
  Player > voice stopped: could not reach "Harbour Lights 01"
  Player > finished series audiobook: could not reach "Dawn Road #1"
  Player > Dawn Road 2 paused: could not reach "Dawn Road #2"
  Player > Chaptered playing: could not reach "Chaptered"
```

No "accessibility problem(s)" block is printed. Wave 4 printed 13 problems on the same chips (37.3 dp). The 4 unreachable routes need fixtures that this emulator lacks (Dawn Road, a book titled "Chaptered"); the "Harbour Lights 01" route fails under the Series grouping. The exit code is 2 because of those 4. This output is the quote for 24.4, 24.5 and 25.4.

### 6.1 steps 5 and 7 (Android)

A book that was finished once behaves differently (defect 2), so the proof uses `Long Walk.m4b`, a book never finished. `dumpsys media_session` gives the session state and position. `progress.db` gives the stored position.

- Step 5: playing at 43.9 s. An EPUB opened (session NONE). The store held `offset_millis` 46095. Continue listening: PLAYING at 46136 ms, one session. The restart at 2 to 3 s of wave 5 did not happen.
- Step 7: playing at about 68 s. Sea Room started (6 s) and played to its end: session NONE. The store held 68373. Continue listening on the first book: PLAYING at 68414 ms. `cmd media_session dispatch pause` paused that book.

### 7.9 on Android

`progress.db` held `progression` 0.225, `locator.locations.progression` 0.45 and `element_locator` for paragraph 12 (set by reading to page 2, closing, then editing the database with the app stopped). The book opened on paragraph 12, not paragraph 24. The sync document written by the app (`StoryArc Library.json` on the share) carried `firstVisibleElement` for `fixture.epub` (cssSelector `:root > :nth-child(2) > :nth-child(13)`, textAfter "Chapter 1, paragraph 12. ...", the publication digest). The cross-platform half (iOS opening the same document) belongs to the iOS lane and was not run here. `fixture.epub` has no long paragraph, so there is no long-paragraph frame.

### 5.4, how the conflicts were made

A second device was simulated by editing the sync document on the share between two syncs. Rule from `ProgressMerge`: a conflict needs a local position that moved since the last sync and a remote position that moved too. One title: the share was edited (fixture 0.9), then the book was read to another page and closed (sync on close). Two titles: the share server was stopped, both books were read locally, the server was restarted with a document that moved both books, and the app was relaunched (sync at launch).

## Owed

- Frame 25.7 on Home as a hero "Resume and Finish" pair: Android Home has "Resume" only on its Continue reading card. No "Finish" button was found on Android Home. The iOS audit part (accessibility audit on `.glassProminent`) belongs to the iOS lane.
- 7.9: the long-paragraph frame (no long paragraph in the fixture) and the same-paragraph check on iOS from this document.
- 5.7: the Unreachable state was not photographed.

## Defects found (not fixed)

1. Landscape rail at rest: with the strip whole the rail draws 5 letters, not many. After one swipe it draws 14. The rest state is as designed by 25.2 (strip scrolls away). Listed so the reader knows the first impression at rest.
2. A book that was finished once restarts at 0 on Continue listening, although a newer position was stored. With Cover Long: `is_finished` 1, `offset_millis` 42128 after an EPUB displaced it at 42 s. Continue listening started at 0. A never-finished book resumes at its stored position (6.1 proof above).
3. A conflict notice that one sync reports is dropped when a second sync with no conflict runs before the Library is shown: launch sync (conflict) followed by "Sync now" (no conflict) left the Library with no notice, and the local positions had already moved to the remote ones. The notice came back on the next run with only one sync. Not proved to be the cause. Repeat: create the conflict, relaunch, then tap Sync now in Settings, then open Library.
4. "127.0.0.1/Sync" (a loopback source from another device) reads "Not answering" while the sentence under it says this device does not try it. The brief expected "Unreachable". The two statements disagree.
5. The cover of "With Cover Long" and "Fixture Publication" draws blank blue: the embedded cover is a solid colour equal to the wash. The pencil edit button is nearly invisible on it. Fixture artefact, not a product fault.

## Changed outside this folder

- `scripts/android-routes.mjs`: four routes, `Library > shelf scrolled`, `Audiobook page > with progress`, `Player > compact bar long playing`, `Settings > Your libraries scrolled`.

## Repeat

```bash
export PATH=$HOME/Library/Android/sdk/platform-tools:$PATH ANDROID_SERIAL=emulator-5554
adb shell settings put system accelerometer_rotation 0; adb shell settings put system user_rotation 1   # landscape
node scripts/capture-android.mjs "Library > shelf scrolled" --out f.png [--dark]
node scripts/capture-android.mjs "Audiobook page > with progress" --out f.png [--dark]
node scripts/capture-android.mjs "Player > compact bar long playing" --out f.png [--dark]
node scripts/capture-android.mjs "Settings > Your libraries scrolled" --out f.png
node scripts/smoke-android.mjs --a11y Player
```

Rotate back afterwards: `user_rotation 0` and `accelerometer_rotation 1`.
