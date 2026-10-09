# Wave 4, Android frames and emulator proofs - 2026-10-09

Device: emulator `storyarc-ci` (API 35, google_apis, arm64), headless, `-memory 2048`. Debug build `com.mecedric.storyarc.debug`, installed from `apps/android/app/build/outputs/apk/debug/app-debug.apk` built at the head of branch `wave-4`. The task text names the package `app.storyarc.debug`. That name is old. Use `com.mecedric.storyarc.debug`.

All frames use the default text size, in light and in dark. Dark frames end in `-dark`.

The fixtures are the OPDS mock on port 4444 and 4447 (and 4999 for a moment, to quiet one banner) and the Kavita mock on port 5000, all serving `node scripts/corpus.mjs /tmp/sa-corpus`. The emulator already held a library from earlier waves, so some rows (Ashfall, Marrowfield) come from that state.

## Frames

| Frames | What they prove |
| --- | --- |
| `android-detail-no-cover*`, `android-detail-no-cover-menu*` | Task 24.1. A coverless page ("Sea Room") shows the drawn well, the 48 dp edit button on the cover and the label "Add a cover". The menu holds "Choose a picture" and "Find a cover on the web" (with the leave-the-app icon and the note). It has no "Find a cover" row because the lookup is off. |
| `android-detail-chosen-cover*`, `android-detail-chosen-cover-menu*` | Task 24.1. After a picture is chosen, the edit button sits on the bottom end corner of the cover. The menu shows the two choose rows, a divider, and "Remove cover" in the error colour as the last row. |
| `android-detail-remove-dialog*` | Task 24.2. "Remove this cover?" says the picture is deleted from this device. It has "Cancel" and "Remove cover". Cancel keeps the picture (the chosen-cover frames in dark were taken after Cancel). |
| `android-kavita-list-no-cover*`, `android-kavita-list-no-cover-menu*` | Tasks 24.1 and 24.7. The reading list "Start here" shows the cover well and the edit button with the label "Add a cover". The menu holds one row, "Choose a picture". |
| `android-kavita-list-cover-chosen*`, `android-kavita-list-cover-chosen-menu*` | Tasks 24.1, 24.2 and 24.7. The chosen cover with its edit button. The menu holds "Choose a picture", "Send this cover to the server", a divider and "Remove cover". |
| `android-player-sleep-chips*` | Task 24.4. The four sleep-timer chips, 60 min and "End of chapter" after a scroll. The dump of this screen gives each chip 48.0 dp high, 8 dp apart (see the proof below). `android-player-unscrolled.png` is the screen before the scroll, where the bottom bar covers the chips. |
| `android-rail-rest*` | Task 24.6. The A to Z rail at rest, on the Library with Sort: Title. 14 of 26 letters are drawn, so the letters thin out. The rail is one `SeekBar` node, "Alphabetical index", 48 x 352 dp. |
| `android-rail-drag*` | Task 24.6. A finger held on the rail at "M". The circle bubble with the letter shows to the left of the finger. The list moved to "Marrowfield". |
| `android-rail-landscape*` | Task 24.6. A phone in landscape. The rail draws one letter ("A"). See defect 1. |
| `android-tap-library-controls*`, `android-tap-downloads*`, `android-tap-settings-downloads*`, `android-tap-search-scopes*` | Task 24.4. One frame of each changed screen that the route map reaches: the Library chips, the Downloads queue row, the limit chips, the search scope chips and the recent searches. |
| `android-shade-resumed-after-kill*` | Task 4.4b. The notification shade after a resume from process death. The row shows the drawn artwork (headphones and "M4B"). Before the fix, the same step gave a row with no picture (`../android-player-2026-10-08/android-shade-resumed-after-kill.png`). |
| `android-detail-on-device-fr.png`, `android-detail-states-fr-a-on-device.png`, `-b-server-title.png`, `-c-server-silent.png` | Lane l10n, French, light. (a) "Sur cet appareil, lisible sans réseau". (b) "De ada · 10.0.2.2, pas sur cet appareil". (c) "De Attic Catalogue, pas sur cet appareil" with "Impossible d’ouvrir ceci tant que ce n’est pas sur cet appareil (3,0 ko)." (the refusal with a size). |
| `android-skipped-list-fr.png`, `android-skipped-list-en.png` | Lane l10n, task 1.8. The sheet "Ce qui n’a pas pu être ouvert" in French and in English. |

## Emulator proofs

### 4.4b, drawn artwork after process death

Run `./resume-after-kill.sh out.png` (light) or `NIGHT=yes ./resume-after-kill.sh out.png` (dark). It plays "Sea Room", pauses at chapter two, runs `am force-stop`, then `cmd media_session dispatch play`, then pulls the shade.

- Before kill: `PAUSED, position=2000`. `shared_prefs/app.storyarc.playback.memory.xml` holds `position=2000`, `index=1` and `artwork=file:///data/user/0/com.mecedric.storyarc.debug/cache/player-artwork/18ioppx.png`.
- After kill: `pidof` empty, no media session for the package.
- After the key: `PLAYING, position=2043`. The shade shows the drawn well. In the dark run, `pidof` showed a process before the key, with no media session. Another component of the app started it. The result is the same.

### 24.5 and 8.1, `scripts/smoke-android.mjs --a11y Player`

The output is in `smoke-android-a11y-player.txt`. It reads:

```
7/11 routes walked and survived
13 accessibility problem(s) across the routes:
  Player: SMALL     View 67.0x37.3dp "5 min"
  Player: SMALL     View 74.7x37.3dp "15 min"
  Player: SMALL     View 74.7x37.3dp "30 min"
  Player: SMALL     View 74.7x37.3dp "45 min"
  Player > compact bar: SMALL     View 411.4x28.6dp "Up next"
  (the same four chips for "Player > Sea Room playing" and "Player > Sea Room paused")
4 could not be reached: Player > voice stopped, Player > finished with a damaged part,
  Player > Dawn Road 2 paused, Player > Chaptered playing
```

The scan is not clean. The cause is the scan, not the chips: it reads the visible bounds of a node. On the Player route the chips sit under the bottom bar, so the visible height is 37.3 dp. After the screen scrolls, the dump gives every chip `[42,1021][218,1147]` and so on: 48.0 dp high, 8 dp from the next, rows 8 dp apart. "Up next" is a heading on Home that the bottom bar also cuts (`android-player-unscrolled.png` shows the same cut for the chips). So the chips pass at 48 dp and the scan still fails. A route that scrolls first, or a scan that reads unclipped bounds, closes it.

### 1.8, French reason in one stop

`adb shell cmd locale set-app-locales com.mecedric.storyarc.debug --locales fr`, then route `Library > skipped list`, then `uiautomator dump`. The entry is one `View` node (`[53,2010][754,2131]`) with two children: the name "Locked Vault.cbz" and "l’archive est protégée par un mot de passe". English control: the same `View` with "the archive is password protected". `content-desc` is empty on every node, so the dump does not show one node that holds both texts. It shows one grouping node with both texts below it. The proof the task names (one `content-desc`) cannot be read from `uiautomator`. TalkBack must confirm the single stop.

## Owed

- Readers-proof frame 1 (backward curl across a chapter end after a resume) and frame 2 (forward chapter-end fold at a high frame rate). The reader opened on "The Long Field" at the first page of Chapter 4, in Curl. A tap on the trailing third and on the leading third, and a swipe, did not turn the page. The floating pill showed instead, in three recordings (`record-android-turn.mjs tap` and the new `back`). I did not find the cause in 20 minutes. The search lists five rows named "The Long Field" (two on device, one from Attic, two from Kavita), so I could not be sure which copy opened. Repeat on a clean emulator with one copy of the book. The new mode is `node scripts/record-android-turn.mjs back --out /tmp/rec`.
- Lane fixes-android: PDF highlight (23.1). A long press on a word in "Field Notes.pdf" selected nothing on this API 35 image. Publication-detail 6.5 frames 1 to 4 were not taken.
- Lane l10n: French states (d) and (e), the French gone state, the iOS-only dialogs, "Colour behind a comic page" in French, and the open failure. The Library list does not reach ", CBZ" or "Harbour Lights" on this emulator, so `Comic reader > adjustments` and `EPUB reader > themes expanded` failed to start. State (c) shows "pas sur cet appareil" instead of "sans réponse pour le moment": the status had not refreshed within three seconds of stopping the mock.
- Task 24.4, the comic adjustments sheet, the EPUB theme swatches and the EPUB selection menu: same reason as above.
- Task 24.6, a wide Android window: not taken.

## Defects found

1. On a phone in landscape the Library gives the list about 35 dp (`android-rail-landscape.png`): the title, the notice, the chips and the status line sit above it and do not scroll. The rail then draws one letter. The rail node is 48 x 40 dp there.
2. The menu on a page with a chosen cover reaches the right screen edge, and its rounded corner is cut (`android-detail-chosen-cover-menu.png`).
3. The sentence under the "Download it" button on a Kavita title page has almost no contrast against the wash (`android-detail-states-fr-b-server-title.png`).
4. In dark, the play triangle on the compact player bar is near black on near black (`android-detail-remove-dialog-dark.png`).
5. The a11y scan counts clipped nodes as small (see 24.5 above).
6. On the Kavita title page, the primary button starts a download at one tap. A "Waiting for Wi-Fi" entry for "The Long Field #1" remains in this emulator's Downloads queue (`android-tap-downloads-dark.png`).

## Changed outside this folder

- `scripts/android-routes.mjs`: three routes, `EPUB reader > Long Field through search`, `... through search contents`, `... through search curl chosen`.
- `scripts/record-android-turn.mjs`: a `back` mode, one tap on the leading third.

## How to repeat

1. `pnpm build:android`, then `adb install -r`. Add `$HOME/Library/Android/sdk/platform-tools` to `PATH`.
2. `node scripts/corpus.mjs /tmp/sa-corpus`. Start `node scripts/opds-server.mjs /tmp/sa-corpus --port 4444` and `node scripts/kavita-server.mjs /tmp/sa-corpus`.
3. `pnpm capture:android "Publication page > Sea Room" --out f.png [--dark]`, `"Kavita > list"`, `"Library > index rail"`, `"Player > Sea Room paused"` (then swipe up 1200 px).
4. Rail drag: `adb shell input motionevent DOWN 1017 1100`, `MOVE` to 1500 in steps, screenshot, `UP`.
