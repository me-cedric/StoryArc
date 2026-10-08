# Covers, part B, Android, 2026-10-08

Visual proof for `cover-for-every-publication` tasks 6.2, 3.3, 6.4, 5.1 and 5.3, and `close-the-audited-gaps` task 7.8. The iOS half is in `../covers-b-ios-2026-10-08/`.

Device: emulator `storyarc-ci` (API 35, google_apis, arm64), headless. Debug build `com.mecedric.storyarc.debug` at commit `62eba386`. The Kavita mock runs on port 5000 (`node scripts/kavita-server.mjs <corpus>`). The app holds it as the source "ada - 10.0.2.2".

## Frames

Each frame has a light, a dark, a largest-text (`-ax`) and a dark largest-text variant where the layout can wrap. Frames without all four variants have no wrap risk.

| Frames | What they prove |
| --- | --- |
| `android-detail-no-cover-lookup-off*` | Task 6.2. A coverless audiobook page ("Sea Room") shows "Choose a cover", "Find a cover on the web" and the note that StoryArc downloads nothing. It does not show "Find a cover". |
| `android-detail-no-cover-lookup-on*` | Task 6.2. After Settings > Privacy > look up missing covers is on, the page also shows "Find a cover". |
| `android-candidate-sheet*` | Task 3.3, partly. The sheet "Choose a cover". The light default frame shows "Looking for covers". The other three show "No candidate was found. Search the web instead, or choose a picture of your own." Candidates with pictures are owed. See below. |
| `android-kavita-list-no-cover*` | Task 5.1. The reading list "Start here" has no cover. The header offers "Choose a cover". |
| `android-kavita-list-cover-chosen*` | Task 5.1. After a picture is chosen, the header shows its thumbnail, "Change cover", "Remove cover" and "Send this cover to the server". |
| `android-kavita-list-send-dialog`, `-dark` | Task 5.3. The dialog "Send this cover to the server" says it changes the cover for everyone who can see the list. |
| `android-kavita-list-menu`, `-dark` | Tasks 6.4 and 7.8. The whole-shelf menu on a reading list shows "Mark as read" and "Download". |
| `android-kavita-collection-menu`, `-dark` | Tasks 6.4 and 7.8. The same menu on the collection "Staff picks". |
| `android-kavita-collection-download-dialog`, `-dark` | Task 7.8. "Keep 2 titles on this device?" with the size sentence. |
| `android-kavita-collection-mark-read-undo`, `-dark` | Task 7.8. After "Mark as read", the snackbar "2 titles changed" with "Undo". |
| `android-kavita-download-server-down.png` | Task 7.8, reviewer fix. With the mock stopped, "Download" says "ada - 10.0.2.2 did not answer, so nothing was started". It does not say that every title is on the device. |

## Emulator proof for task 5.3

Steps: start the mock, choose `list-cover.png` on the list "Start here", tap "Send this cover to the server", tap "Send".

- Before: `GET /api/Image/readinglist-cover?readingListId=1` answered `image/png`, 1686 bytes, md5 `d905f764f7de2f872d245fa5603e8525`.
- The mock log shows `200 POST /api/Upload/reading-list`.
- After: the same route answered `image/jpeg`, 2970 bytes, md5 `b076cd4925d1349f2ea066332ec55626`.
- The app's stored cover file for the list (`files/cover-overrides/-7ue0ah5hzquf`, key `srv:...:list:1`) has the same md5. The server serves the bytes the app sent.

The live Kavita was not called.

## Owed

- Task 3.3, candidates with pictures on the sheet. The emulator cannot reach Open Library. Chrome on the emulator shows `NET::ERR_CERT_AUTHORITY_INVALID` for `https://openlibrary.org`, because this network intercepts TLS with a certificate authority the emulator does not trust. The app then finds no candidate for any title, also for "Treasure Island" with no author. I did not add the authority to the emulator trust store. Repeat on a network without TLS interception.

## How to repeat

1. `node scripts/corpus.mjs /tmp/corpus`, then `node scripts/kavita-server.mjs /tmp/corpus`.
2. `pnpm build:android` and `adb install -r`. Push `list-cover.png` to `/sdcard/Download`.
3. Add the mock: `pnpm capture:android "Sources > add kavita mock" --out /tmp/x.png`.
4. `pnpm capture:android "Kavita > list" --out f.png [--dark] [--font-scale 2.0]`. The other routes are `Kavita > collection*`, `Kavita > list send confirmation` and `Kavita > list whole shelf menu`.
5. Coverless page: `pnpm capture:android "Publication page > no cover > find a cover" --out f.png`. The lookup-on frames need `Settings > Privacy > cover lookup on` first.
